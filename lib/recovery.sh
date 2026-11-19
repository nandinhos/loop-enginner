#!/usr/bin/env bash
# Debug sistematico, lock de concorrencia, pausa graciosa e retomada segura.
# Carregado via `source` por lib/loop.sh.

RECOVERY_DIR="${STATE_DIR:-.loop-enginner/state}/recovery"
SESSION_FILE="${STATE_DIR:-.loop-enginner/state}/session.tsv"
LOCK_FILE="${STATE_DIR:-.loop-enginner/state}/run.lock"
PAUSE_FILE="${STATE_DIR:-.loop-enginner/state}/pause.request"

declare -A SESSION_META=()
LOCK_HELD=0
RESUME_CLEANED_PHASE=""
RESUME_LAST_GATE=""
RESUME_LAST_CAUSE_FILE=""
RESUME_LAST_DIFF_FILE=""
RESUME_LESSONS_FILE=""

_rec_log() {
  if declare -F log >/dev/null 2>&1; then log "$1"; else printf '[recovery] %s\n' "$1"; fi
}

_rec_warn() {
  if declare -F warn >/dev/null 2>&1; then warn "$1"; else printf '[recovery] aviso: %s\n' "$1" >&2; fi
}

_rec_fail() {
  if declare -F fail >/dev/null 2>&1; then fail "$1"; else printf '[recovery] erro: %s\n' "$1" >&2; fi
}

_rec_sanitize() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

recovery_init_dirs() {
  STATE_DIR="${STATE_DIR:-.loop-enginner/state}"
  RECOVERY_DIR="$STATE_DIR/recovery"
  SESSION_FILE="$STATE_DIR/session.tsv"
  LOCK_FILE="$STATE_DIR/run.lock"
  PAUSE_FILE="$STATE_DIR/pause.request"
  mkdir -p "$STATE_DIR" "$RECOVERY_DIR"
}

recovery_lock_acquire() {
  recovery_init_dirs
  if [ -f "$LOCK_FILE" ]; then
    local owner_pid
    owner_pid="$(cut -f1 "$LOCK_FILE" 2>/dev/null | head -n 1 || true)"
    if [[ "$owner_pid" =~ ^[0-9]+$ ]] && [ "$owner_pid" != "$$" ]; then
      if kill -0 "$owner_pid" 2>/dev/null; then
        _rec_fail "Ja existe um run ativo neste repositorio (PID $owner_pid)."
        _rec_fail "Acompanhe com 'loop-enginner watch' ou solicite pausa com 'loop-enginner pause'."
        return 1
      fi
      _rec_warn "Lock orfao encontrado de processo encerrado (PID $owner_pid); assumindo lock."
    fi
  fi

  local tmp="$LOCK_FILE.$$"
  printf '%s\t%s\n' "$$" "$(date +%s)" > "$tmp"
  mv -f "$tmp" "$LOCK_FILE"
  LOCK_HELD=1
  return 0
}

recovery_lock_release() {
  [ "${LOCK_HELD:-0}" -eq 1 ] || return 0
  if [ -f "$LOCK_FILE" ]; then
    local owner_pid
    owner_pid="$(cut -f1 "$LOCK_FILE" 2>/dev/null | head -n 1 || true)"
    if [ -z "$owner_pid" ] || [ "$owner_pid" = "$$" ]; then
      rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
  fi
  LOCK_HELD=0
  return 0
}

recovery_pause_requested() {
  [ -f "$PAUSE_FILE" ]
}

recovery_pause_clear() {
  rm -f "$PAUSE_FILE" 2>/dev/null || true
}

recovery_session_get() {
  printf '%s' "${SESSION_META[$1]:-}"
}

recovery_session_read() {
  SESSION_META=()
  recovery_init_dirs
  [ -f "$SESSION_FILE" ] || return 1
  local k v
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    SESSION_META["$k"]="$v"
  done < "$SESSION_FILE"
  return 0
}

recovery_session_write() {
  recovery_init_dirs
  SESSION_META[updated_at]="$(date +%s)"
  local tmp="$SESSION_FILE.$$" k v
  {
    for k in state phase_num phase_file phase_title base_head run_start_head \
             input_file input_stamp engine fallback_chain active_provider \
             test_cmd verify_mode max_cycles last_gate last_cause_file \
             last_diff_file lessons_file untracked_before_file updated_at; do
      v="$(_rec_sanitize "${SESSION_META[$k]:-}")"
      printf '%s\t%s\n' "$k" "$v"
    done
  } > "$tmp"
  mv -f "$tmp" "$SESSION_FILE"
  return 0
}

recovery_snapshot_untracked() {
  local out_file="$1"
  mkdir -p "$(dirname "$out_file")"
  git ls-files --others --exclude-standard > "$out_file" 2>/dev/null || : > "$out_file"
}

_rec_phase_slug() {
  local p="${1:-0}"
  if [[ "$p" =~ ^[0-9]+$ ]]; then
    printf 'phase-%02d' "$((10#$p))"
  else
    printf 'phase-%s' "$p"
  fi
}

recovery_record_lesson() {
  local phase_num="$1" gate="$2" cause_file="$3" diff_file="${4:-}" provider="${5:-${ACTIVE_PROVIDER:-${ENGINE:-desconhecido}}}"
  recovery_init_dirs
  local slug lessons_file
  slug="$(_rec_phase_slug "$phase_num")"
  lessons_file="$RECOVERY_DIR/${slug}-lessons.md"
  {
    printf '### Tentativa em %s (provider: %s | gate: %s)\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$provider" "${gate:-desconhecido}"
    if [ -n "$cause_file" ] && [ -s "$cause_file" ]; then
      printf -- '- Causa observada:\n'
      head -n 15 "$cause_file" | sed 's/^/  /'
    else
      printf -- '- Causa observada: sessao interrompida ou encerrada sem causa detalhada.\n'
    fi
    if [ -n "$diff_file" ]; then
      printf -- '- Patch arquivado: %s\n' "$diff_file"
    fi
    printf '\n'
  } >> "$lessons_file"
  RESUME_LESSONS_FILE="$lessons_file"
  printf '%s' "$lessons_file"
}

_recovery_is_in_before() {
  local path="$1" before_file="$2"
  [ -n "$before_file" ] && [ -f "$before_file" ] && grep -qxF -- "$path" "$before_file" 2>/dev/null
}

_recovery_archive_dirty() {
  local phase_num="$1" base_head="$2" before_file="$3" patch_file="$4"
  {
    printf '# Patch de recuperacao da Fase %s\n' "$phase_num"
    printf '# Data: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '# Base HEAD: %s\n\n' "$base_head"
    printf '=== GIT DIFF HEAD ===\n'
    git diff HEAD 2>/dev/null || true
    printf '\n=== UNTRACKED CRIADOS NA FASE ===\n'
    local u
    while IFS= read -r -d '' u; do
      case "$u" in
        .loop-enginner|.loop-enginner/*) continue ;;
      esac
      if _recovery_is_in_before "$u" "$before_file"; then
        continue
      fi
      printf -- '--- %s ---\n' "$u"
      if [ -f "$u" ]; then
        head -n 80 "$u" 2>/dev/null || true
      fi
      printf '\n'
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null || true)
  } > "$patch_file"
}

recovery_prepare_resume() {
  recovery_init_dirs
  RESUME_CLEANED_PHASE=""
  RESUME_LAST_GATE=""
  RESUME_LAST_CAUSE_FILE=""
  RESUME_LAST_DIFF_FILE=""
  RESUME_LESSONS_FILE=""

  local dirty
  dirty="$(git status --porcelain 2>/dev/null || true)"

  if ! recovery_session_read; then
    if [ -n "$dirty" ]; then
      _rec_fail "Arvore de trabalho suja sem sessao recuperavel em $SESSION_FILE."
      _rec_fail "Fail-closed: nenhum arquivo foi descartado. Commite ou limpe manualmente."
      return 1
    fi
    return 0
  fi

  local st phase_num base_head before_file
  st="${SESSION_META[state]:-}"
  phase_num="${SESSION_META[phase_num]:-}"
  base_head="${SESSION_META[base_head]:-}"
  before_file="${SESSION_META[untracked_before_file]:-}"

  if [ "$st" = "finished" ]; then
    if [ -n "$dirty" ]; then
      _rec_fail "Ultimo run ja terminou (state=finished), mas ha alteracoes manuais na arvore."
      _rec_fail "Fail-closed: commite ou descarte manualmente antes de rodar."
      return 1
    fi
    return 0
  fi

  # Arvore limpa: preserva contexto da fase pendente/pausada para debug sistematico se houver.
  if [ -z "$dirty" ]; then
    if [ -n "$phase_num" ]; then
      RESUME_CLEANED_PHASE="$phase_num"
      RESUME_LAST_GATE="${SESSION_META[last_gate]:-}"
      RESUME_LAST_CAUSE_FILE="${SESSION_META[last_cause_file]:-}"
      RESUME_LAST_DIFF_FILE="${SESSION_META[last_diff_file]:-}"
      RESUME_LESSONS_FILE="${SESSION_META[lessons_file]:-}"
    fi
    return 0
  fi

  case "$st" in
    failed|paused|running) ;;
    *)
      _rec_fail "Estado de sessao invalido para limpeza automatica ('$st') com arvore suja."
      return 1
      ;;
  esac

  if [ -z "$phase_num" ]; then
    _rec_fail "Arvore suja fora de uma fase incompleta aberta (phase_num vazio)."
    _rec_fail "Fail-closed: alteracoes manuais externas preservadas; commite ou descarte manualmente."
    return 1
  fi

  local cur_head
  cur_head="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$base_head" ] || [ -z "$cur_head" ] || [ "$cur_head" != "$base_head" ]; then
    _rec_fail "HEAD atual (${cur_head:-?}) difere de base_head registrado (${base_head:-?})."
    _rec_fail "Fail-closed: commits externos detectados; nada foi descartado."
    return 1
  fi

  local ts slug patch_file
  ts="$(date '+%Y%m%d-%H%M%S')"
  slug="$(_rec_phase_slug "$phase_num")"
  patch_file="$RECOVERY_DIR/${slug}-${ts}.patch"

  _recovery_archive_dirty "$phase_num" "$base_head" "$before_file" "$patch_file"

  git reset -q HEAD -- . >/dev/null 2>&1 || true
  git checkout -q -- . >/dev/null 2>&1 || true

  local u dir
  while IFS= read -r -d '' u; do
    case "$u" in
      .loop-enginner|.loop-enginner/*) continue ;;
    esac
    if _recovery_is_in_before "$u" "$before_file"; then
      continue
    fi
    rm -f -- "$u" 2>/dev/null || true
    dir="$(dirname "$u")"
    while [ "$dir" != "." ] && [ "$dir" != "/" ] && [ "$dir" != ".loop-enginner" ]; do
      rmdir "$dir" 2>/dev/null || break
      dir="$(dirname "$dir")"
    done
  done < <(git ls-files --others --exclude-standard -z 2>/dev/null || true)

  dirty="$(git status --porcelain 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    _rec_fail "Restaram alteracoes nao pertencentes a fase incompleta apos limpeza segura:"
    printf '%s\n' "$dirty" | sed 's/^/    /' >&2
    return 1
  fi

  RESUME_CLEANED_PHASE="$phase_num"
  RESUME_LAST_GATE="${SESSION_META[last_gate]:-interrupcao inesperada}"
  RESUME_LAST_CAUSE_FILE="${SESSION_META[last_cause_file]:-}"
  RESUME_LAST_DIFF_FILE="$patch_file"
  RESUME_LESSONS_FILE="${SESSION_META[lessons_file]:-}"
  if [ -z "$RESUME_LESSONS_FILE" ] && [ -f "$RECOVERY_DIR/${slug}-lessons.md" ]; then
    RESUME_LESSONS_FILE="$RECOVERY_DIR/${slug}-lessons.md"
  fi
  if [ -z "$RESUME_LESSONS_FILE" ]; then
    RESUME_LESSONS_FILE="$(recovery_record_lesson "$phase_num" "$RESUME_LAST_GATE" "$RESUME_LAST_CAUSE_FILE" "$patch_file")"
  fi

  SESSION_META[last_diff_file]="$patch_file"
  SESSION_META[lessons_file]="$RESUME_LESSONS_FILE"
  recovery_session_write

  _rec_log "Retomada segura (Fase $phase_num): trabalho parcial arquivado em $patch_file e arvore restaurada em ${base_head:0:7}"
  return 0
}

recovery_systematic_debug_block() {
  local gate="${1:-}" cause="${2:-}" diff_file="${3:-}" lessons_file="${4:-}"
  cat <<'SDEBUG'

## Protocolo de Debug Sistematico (obrigatorio apos falha)
Voce esta corrigindo ou retomando esta fase apos uma falha anterior. NAO repita cegamente a mesma abordagem que falhou:
1. Inspecione a causa real abaixo, os logs completos em .loop-enginner/logs/ e o codigo real antes de editar qualquer arquivo.
2. Consulte a documentacao oficial da stack/API via **Context7** quando disponivel nesta sessao para confirmar contratos e assinaturas exatas (se Context7 nao estiver disponivel no ambiente, valide pelos docs locais do repo e pelos testes reais — nao bloqueie por isso).
3. Consulte a **memoria disponivel** (hub de memoria como dev-memory, memoria da sessao e licoes locais em .loop-enginner/state/recovery/) para verificar padroes de erro ja ocorridos; essa consulta e estritamente opcional e NAO bloqueante caso nenhum hub de memoria esteja disponivel.
4. Formule 1 hipotese objetiva e falsificavel sobre a causa raiz, confirme por evidencia ou teste minimo, aplique a correcao cirurgica e comprove rodando a suite de testes do projeto.
SDEBUG

  if [ -n "$gate" ] || [ -n "$cause" ]; then
    echo
    echo "### Falha anterior observada (${gate:-gate desconhecido})"
    if [ -n "$cause" ]; then
      echo '```'
      printf '%s\n' "$cause"
      echo '```'
    fi
  fi

  if [ -n "$diff_file" ] && [ -s "$diff_file" ]; then
    echo
    echo "### Resumo da tentativa anterior arquivada ($diff_file)"
    echo '```diff'
    head -n 60 "$diff_file"
    echo '```'
  fi

  if [ -n "$lessons_file" ] && [ -s "$lessons_file" ]; then
    echo
    echo "### Licoes locais registradas desta fase ($lessons_file)"
    echo '```markdown'
    tail -n 40 "$lessons_file"
    echo '```'
  fi
}
