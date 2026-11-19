#!/usr/bin/env bash
# report.sh — gera .loop-enginner/state/report.md e exibe relatorio estilizado
# pos-execucao a partir de evidencias observadas (estado TSV, git e logs).
set -euo pipefail

TARGET="."
OUTPUT_MD=false
SAVE_ONLY=false
USE_COLOR=true
FORCE_COLOR=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || { printf 'loop-enginner report: --target exige um diretorio\n' >&2; exit 1; }
      TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --md)       OUTPUT_MD=true; shift ;;
    --save-only) SAVE_ONLY=true; shift ;;
    --no-color) USE_COLOR=false; shift ;;
    --color)    FORCE_COLOR=true; shift ;;
    -h|--help)
      cat <<'EOF'
Uso: loop-enginner report [--target DIR] [--md] [--color] [--no-color] [--save-only]
Gera e exibe o relatorio detalhado do ultimo run em .loop-enginner/state/report.md.
EOF
      exit 0
      ;;
    *) TARGET="$1"; shift ;;
  esac
done

$FORCE_COLOR || [ -t 1 ] || USE_COLOR=false

REPO="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  if [ -d "$TARGET/.loop-enginner/state" ]; then
    REPO="$(cd "$TARGET" && pwd)"
  else
    printf 'loop-enginner report: erro: diretorio nao e repositorio git nem possui .loop-enginner/state: %s\n' "$TARGET" >&2
    exit 1
  fi
fi

STATE_DIR="$REPO/.loop-enginner/state"
RUN_STATE="$STATE_DIR/run.tsv"
HISTORY_FILE="$STATE_DIR/history.tsv"
RECOVERY_STATE="$STATE_DIR/recovery.tsv"
SESSION_FILE="$STATE_DIR/session.tsv"
RECOVERY_DIR="$STATE_DIR/recovery"
LOG_DIR="$REPO/.loop-enginner/logs"
REPORT_MD="$STATE_DIR/report.md"

[ -f "$RUN_STATE" ] || {
  printf 'loop-enginner report: nenhum estado em %s\n' "$RUN_STATE" >&2
  exit 1
}

if $USE_COLOR; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_BORDER=$'\033[38;2;38;56;77m'
  C_PRIMARY=$'\033[38;2;96;165;250m'
  C_CYAN=$'\033[38;2;56;189;248m'
  C_SUCCESS=$'\033[38;2;52;211;153m'
  C_WARNING=$'\033[38;2;251;191;36m'
  C_DANGER=$'\033[38;2;251;113;133m'
  C_WHITE=$'\033[38;2;229;237;247m'
  C_MUTED=$'\033[38;2;155;170;189m'
else
  C_RESET=""; C_BOLD=""; C_BORDER=""; C_PRIMARY=""; C_CYAN=""
  C_SUCCESS=""; C_WARNING=""; C_DANGER=""; C_WHITE=""; C_MUTED=""
fi

declare -A META RECOVERY SESSION PH_STATUS PH_ATTEMPT PH_GATES PH_TITLE
declare -A PH_HIST_DONE PH_COMMIT_HASH PH_COMMIT_SUBJ PH_COMMIT_PROV PH_COMMIT_DUR PH_COMMIT_CYCLES
declare -A PH_TASK_TOTAL PH_TASK_DONE
declare -a PHASE_NUMS=() FALLBACK_EVENTS=() RETRY_EVENTS=()

rep_fmt_duration() {
  local t="${1:-0}" h m s
  [[ "$t" =~ ^[0-9]+$ ]] || { printf '%s' '?'; return 0; }
  h=$((t / 3600)); m=$(((t % 3600) / 60)); s=$((t % 60))
  if [ "$h" -gt 0 ]; then printf '%dh %02dm %02ds' "$h" "$m" "$s"
  elif [ "$m" -gt 0 ]; then printf '%dm %02ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

rep_fmt_epoch() {
  local ep="${1:-}"
  [[ "$ep" =~ ^[0-9]+$ ]] || { printf '—'; return 0; }
  date -d "@$ep" '+%d/%m/%Y %H:%M:%S' 2>/dev/null || printf '%s' "$ep"
}

rep_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'
}

rep_load_state() {
  local kind a b c d e
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      META) META["$a"]="${b:-}" ;;
      PHASE)
        PHASE_NUMS+=("$a")
        PH_STATUS["$a"]="${b:-pending}"
        PH_ATTEMPT["$a"]="${c:-0}"
        PH_GATES["$a"]="${d:-pending pending pending pending}"
        PH_TITLE["$a"]="${e:-}"
        PH_TASK_TOTAL["$a"]=0
        PH_TASK_DONE["$a"]=0
        ;;
      TASK)
        PH_TASK_TOTAL["$a"]=$(( ${PH_TASK_TOTAL["$a"]:-0} + 1 ))
        [ "${c:-}" = "done" ] && PH_TASK_DONE["$a"]=$(( ${PH_TASK_DONE["$a"]:-0} + 1 ))
        ;;
    esac
  done < "$RUN_STATE"

  if [ -f "$RECOVERY_STATE" ]; then
    while IFS=$'\t' read -r kind a b; do
      [ "$kind" = "META" ] || continue
      RECOVERY["$a"]="${b:-}"
    done < "$RECOVERY_STATE"
  fi

  if [ -f "$SESSION_FILE" ]; then
    while IFS=$'\t' read -r a b; do
      [ -n "$a" ] || continue
      SESSION["$a"]="${b:-}"
    done < "$SESSION_FILE"
  fi

  if [ -f "$HISTORY_FILE" ]; then
    local ts ev ph det started_bound=0
    if [[ "${META[started]:-0}" =~ ^[0-9]+$ ]] && [ "${META[started]:-0}" -gt 0 ]; then
      started_bound=$(( META[started] - 2 ))
    fi
    while IFS=$'\t' read -r ts ev ph det; do
      case "$ev" in
        phase_done|phase_already_done)
          [ -n "$ph" ] && PH_HIST_DONE["$ph"]="$ev"
          ;;
        phase_commit)
          local ch cs cp cd cc
          IFS='|' read -r ch cs cp cd cc <<< "${det:-}"
          [ -n "$ph" ] || continue
          PH_COMMIT_HASH["$ph"]="$ch"
          PH_COMMIT_SUBJ["$ph"]="$cs"
          PH_COMMIT_PROV["$ph"]="$cp"
          PH_COMMIT_DUR["$ph"]="$cd"
          PH_COMMIT_CYCLES["$ph"]="$cc"
          ;;
        provider_fallback)
          if [ "$started_bound" -eq 0 ] || { [[ "${ts:-0}" =~ ^[0-9]+$ ]] && [ "$ts" -ge "$started_bound" ]; }; then
            FALLBACK_EVENTS+=("Fase ${ph:-?}: ${det:-}")
          fi
          ;;
        supervisor_retry)
          if [ "$started_bound" -eq 0 ] || { [[ "${ts:-0}" =~ ^[0-9]+$ ]] && [ "$ts" -ge "$started_bound" ]; }; then
            RETRY_EVENTS+=("${det:-}")
          fi
          ;;
      esac
    done < "$HISTORY_FILE"
  fi
}

TOK_HAS_DATA=0
TOK_IN=0
TOK_OUT=0
TOK_CACHE_READ=0
TOK_CACHE_CREATE=0
TOK_TOTAL=0
TOK_COST="0"
TOK_MODELS=""

rep_parse_tokens() {
  local started="${META[started]:-0}" f m
  local -a logs=() all_logs=()
  for f in "$LOG_DIR"/phase-*.log; do
    [ -s "$f" ] || continue
    all_logs+=("$f")
    if [[ "$started" =~ ^[0-9]+$ ]] && [ "$started" -gt 0 ]; then
      m="$(rep_mtime "$f")"
      if [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -ge $((started - 2)) ]; then
        logs+=("$f")
      fi
    fi
  done
  if [ "${#logs[@]}" -eq 0 ] && [ "${#all_logs[@]}" -gt 0 ]; then
    logs=("${all_logs[@]}")
  fi
  [ "${#logs[@]}" -gt 0 ] || return 0

  local parsed
  parsed="$(awk '
    function clean_num(s) {
      gsub(/,/, "", s)
      return s + 0
    }
    function add_model(m) {
      if (m != "" && !(m in seen_m)) {
        seen_m[m] = 1
        models = (models == "" ? m : models ", " m)
      }
    }
    function extract_int(line, key,    tmp) {
      if (match(line, "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+")) {
        tmp = substr(line, RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", tmp)
        return tmp + 0
      }
      return -1
    }
    function extract_float(line, key,    tmp) {
      if (match(line, "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+(\\.[0-9]+)?")) {
        tmp = substr(line, RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", tmp)
        return tmp + 0.0
      }
      return -1
    }
    {
      if (expect_codex_val) {
        expect_codex_val = 0
        if (match($0, /^[[:space:]]*[0-9][0-9,]*[[:space:]]*$/)) {
          val = clean_num($0)
          tot_tok += val
          has_data = 1
          next
        }
      }

      if ($0 ~ /"type"[[:space:]]*:[[:space:]]*"result"/) {
        v = extract_int($0, "input_tokens")
        if (v >= 0) { in_tok += v; has_data = 1 }
        v = extract_int($0, "output_tokens")
        if (v >= 0) { out_tok += v; has_data = 1 }
        v = extract_int($0, "cache_read_input_tokens")
        if (v >= 0) { cr_tok += v; has_data = 1 }
        v = extract_int($0, "cache_creation_input_tokens")
        if (v >= 0) { cc_tok += v; has_data = 1 }
        c = extract_float($0, "total_cost_usd")
        if (c >= 0) { cost += c; has_data = 1 }
        if (match($0, /"modelUsage"[[:space:]]*:[[:space:]]*[{][[:space:]]*"[^"]+"/)) {
          m = substr($0, RSTART, RLENGTH)
          sub(/^"modelUsage"[[:space:]]*:[[:space:]]*[{][[:space:]]*"/, "", m)
          sub(/"$/, "", m)
          add_model(m)
        } else if (match($0, /"model"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
          m = substr($0, RSTART, RLENGTH)
          sub(/^"model"[[:space:]]*:[[:space:]]*"/, "", m)
          sub(/"$/, "", m)
          add_model(m)
        }
        next
      }

      vi = extract_int($0, "input_tokens")
      vo = extract_int($0, "output_tokens")
      vt = extract_int($0, "total_tokens")
      if (vi >= 0 || vo >= 0 || vt >= 0) {
        if (vi >= 0) in_tok += vi
        if (vo >= 0) out_tok += vo
        if (vt >= 0) tot_tok += vt
        has_data = 1
        next
      }

      if (tolower($0) ~ /tokens used/) {
        if (match($0, /tokens used[^0-9]*[0-9][0-9,]*/)) {
          seg = substr($0, RSTART, RLENGTH)
          sub(/^[^0-9]*/, "", seg)
          tot_tok += clean_num(seg)
          has_data = 1
        } else {
          expect_codex_val = 1
        }
      }
    }
    END {
      if (tot_tok == 0 && (in_tok + out_tok) > 0) {
        tot_tok = in_tok + out_tok
      }
      printf "%d\t%d\t%d\t%d\t%d\t%d\t%.4f\t%s\n", has_data, in_tok, out_tok, cr_tok, cc_tok, tot_tok, cost, models
    }
  ' "${logs[@]}" 2>/dev/null || true)"

  if [ -n "$parsed" ]; then
    IFS=$'\t' read -r TOK_HAS_DATA TOK_IN TOK_OUT TOK_CACHE_READ TOK_CACHE_CREATE TOK_TOTAL TOK_COST TOK_MODELS <<< "$parsed"
  fi
}

rep_format_tokens() {
  local eff="${META[provider]:-${META[engine]:-engine}}"
  if [ "$TOK_HAS_DATA" -eq 1 ]; then
    local parts="total=${TOK_TOTAL}"
    [ $((TOK_IN + TOK_OUT)) -gt 0 ] && parts="in=${TOK_IN} · out=${TOK_OUT} · ${parts}"
    [ "$TOK_CACHE_READ" -gt 0 ] && parts+=" · cache_read=${TOK_CACHE_READ}"
    if [ "$TOK_COST" != "0.0000" ] && [ "$TOK_COST" != "0" ]; then
      parts+=" · custo=\$${TOK_COST}"
    fi
    printf '%s' "$parts"
  else
    printf 'n/d (modo text — %s nao reporta contagem)' "$eff"
  fi
}

rep_gate_marks() {
  local spec="${1:-pending pending pending pending}" st out="" i=0
  # shellcheck disable=SC2206
  local -a g=( $spec )
  for i in 0 1 2 3; do
    st="${g[$i]:-pending}"
    [ "$i" -gt 0 ] && out+=" "
    case "$st" in
      pass) out+="G${i}✓" ;;
      fail) out+="G${i}✗" ;;
      skip) out+="G${i}–" ;;
      run)  out+="G${i}▶" ;;
      *)    out+="G${i}·" ;;
    esac
  done
  printf '%s' "$out"
}

rep_phase_diffstat() {
  local hash="$1"
  [ -n "$hash" ] || { printf '—'; return 0; }
  local stat
  stat="$(git -C "$REPO" show --shortstat --format='' "$hash" 2>/dev/null | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"
  [ -n "$stat" ] && printf '%s' "$stat" || printf 'sem mudancas'
}

rep_write_markdown() {
  local total_ph="$1" done_ph="$2" skip_ph="$3" fail_ph="$4" total_tk="$5" done_tk="$6"
  local started="${META[started]:-0}" ended="${META[ended]:-$(date +%s)}"
  local dur="0"
  if [[ "$started" =~ ^[0-9]+$ ]] && [[ "$ended" =~ ^[0-9]+$ ]] && [ "$ended" -ge "$started" ]; then
    dur="$((ended - started))"
  fi

  local st="${META[status]:-unknown}"
  local sup_st="${RECOVERY[supervisor_state]:-desativado}"
  local retries="${RECOVERY[retries_used]:-0}/${RECOVERY[retries_limit]:-${LOOP_ENGINNER_MAX_RECOVERIES:-3}}"
  local eff_prov="${META[provider]:-${META[engine]:-—}}"
  local model_disp="${META[model]:-—}"
  [ "$model_disp" = "—" ] && [ -n "$TOK_MODELS" ] && model_disp="$TOK_MODELS"
  local tok_str
  tok_str="$(rep_format_tokens)"

  mkdir -p "$STATE_DIR"
  local tmp="$REPORT_MD.$$"
  {
    printf '# Relatorio Pos-Execucao — Loop Enginner\n\n'
    printf -- '- **Projeto:** `%s`\n' "${META[project]:-$(basename "$REPO")}"
    printf -- '- **Branch:** `%s`\n' "${META[branch]:-$(git -C "$REPO" branch --show-current 2>/dev/null || printf 'detached')}"
    printf -- '- **Run ID:** `%s`\n' "${META[run]:-?}"
    printf -- '- **Status Final:** `%s` (supervisor: `%s`)\n' "$st" "$sup_st"
    printf -- '- **Documento de Fases:** `%s`\n\n' "${META[input]:-?}"

    printf '## Metricas de Tempo e Execucao\n\n'
    printf '| Metrica | Valor |\n|---|---|\n'
    printf '| Inicio | %s |\n' "$(rep_fmt_epoch "$started")"
    printf '| Fim | %s |\n' "$(rep_fmt_epoch "$ended")"
    printf '| Duracao total | %s |\n' "$(rep_fmt_duration "$dur")"
    printf '| Fases | %s/%s concluidas (%s falharam, %s puladas) |\n' "$done_ph" "$total_ph" "$fail_ph" "$skip_ph"
    printf '| Tasks | %s/%s |\n' "$done_tk" "$total_tk"
    printf '| Retomadas do supervisor | %s |\n\n' "$retries"

    printf '## Modelo, Provider e Tokens\n\n'
    printf '| Campo | Valor |\n|---|---|\n'
    printf '| Engine primaria | `%s` |\n' "${META[engine]:-—}"
    printf '| Provider efetivo | `%s` |\n' "$eff_prov"
    printf '| Cadeia de fallback | `%s` |\n' "${META[fallback_chain]:-—}"
    printf '| Modelo | `%s` |\n' "$model_disp"
    printf '| Esforco / Profile | `%s` / `%s` |\n' "${META[reasoning_effort]:-—}" "${META[profile]:-—}"
    printf '| Tokens observados | %s |\n\n' "$tok_str"

    if [ "${#FALLBACK_EVENTS[@]}" -gt 0 ]; then
      printf '### Transicoes de Fallback\n\n'
      local fb
      for fb in "${FALLBACK_EVENTS[@]}"; do printf -- '- %s\n' "$fb"; done
      printf '\n'
    fi

    printf '## Entregas por Fase\n\n'
    printf '| Fase | Titulo | Status | Commit | Diff | Duracao | Ciclos | Provider | Gates |\n'
    printf '|---|---|---|---|---|---|---|---|---|\n'
    local num pst eff_st ch cs diff_s pdur pcyc pprov pgates
    for num in "${PHASE_NUMS[@]}"; do
      pst="${PH_STATUS[$num]}"
      eff_st="$pst"
      [ "$eff_st" = "skipped" ] && [ -n "${PH_HIST_DONE[$num]:-}" ] && eff_st="done (*)"
      ch="${PH_COMMIT_HASH[$num]:-—}"
      cs="${PH_COMMIT_SUBJ[$num]:-—}"
      diff_s="$(rep_phase_diffstat "${PH_COMMIT_HASH[$num]:-}")"
      pdur="${PH_COMMIT_DUR[$num]:-—}"
      [[ "$pdur" =~ ^[0-9]+$ ]] && pdur="$(rep_fmt_duration "$pdur")"
      pcyc="${PH_COMMIT_CYCLES[$num]:-${PH_ATTEMPT[$num]:-0}}"
      pprov="${PH_COMMIT_PROV[$num]:-$eff_prov}"
      pgates="$(rep_gate_marks "${PH_GATES[$num]:-}")"
      printf '| F%s | %s | %s | `%s` %s | %s | %s | %s | `%s` | `%s` |\n' \
        "$num" "${PH_TITLE[$num]}" "$eff_st" "$ch" "${cs# }" "$diff_s" "$pdur" "$pcyc" "$pprov" "$pgates"
    done
    printf '\n'

    printf '## Trilha de Recuperacao e Debug Sistematico\n\n'
    if [ "${#RETRY_EVENTS[@]}" -gt 0 ] || [ "$st" != "finished" ] || [ -n "${SESSION[last_diff_file]:-}" ]; then
      printf -- '- **Ultima acao do supervisor:** %s\n' "${RECOVERY[last_action]:-nenhuma}"
      [ -n "${META[last_error]:-}" ] && printf -- '- **Ultimo erro:** `%s`\n' "${META[last_error]}"
      [ -n "${SESSION[last_gate]:-}" ] && printf -- '- **Ultimo gate reprovado:** `%s`\n' "${SESSION[last_gate]}"
      local rv
      for rv in "${RETRY_EVENTS[@]+"${RETRY_EVENTS[@]}"}"; do
        printf -- '- %s\n' "$rv"
      done
      if [ -d "$RECOVERY_DIR" ]; then
        local rf
        for rf in "$RECOVERY_DIR"/*.patch "$RECOVERY_DIR"/*-lessons.md; do
          [ -e "$rf" ] || continue
          printf -- '- Evidencia local: `%s`\n' "${rf#"$REPO"/}"
        done
      fi
    else
      printf -- '- Nenhuma falha ou retomada necessaria nesta execucao.\n'
    fi
  } > "$tmp"
  mv -f "$tmp" "$REPORT_MD"
}

rep_repeat_v() {
  local __ch="$2" __n="$3" __out="" __i
  for ((__i=0; __i<__n; __i++)); do __out+="$__ch"; done
  printf -v "$1" '%s' "$__out"
}

rep_pad_v() {
  local __s="$2" __w="$3" __n=${#2}
  if [ "$__n" -gt "$__w" ]; then
    if [ "$__w" -gt 1 ]; then __s="${__s:0:__w-1}…"; else __s="${__s:0:__w}"; fi
    __n=$__w
  fi
  printf -v "$1" '%s%*s' "$__s" $((__w - __n)) ''
}

rep_box_open() {
  local w="$1" title="$2" pre rem l r
  local inner=$((w - 2))
  pre=$(( (inner - ${#title} - 2) / 2 ))
  [ "$pre" -lt 0 ] && pre=0
  rem=$(( inner - pre - ${#title} - 2 ))
  [ "$rem" -lt 0 ] && rem=0
  rep_repeat_v l '─' "$pre"
  rep_repeat_v r '─' "$rem"
  printf '%s┌%s %s%s%s %s┐%s\n' "$C_BORDER" "$l" "$C_PRIMARY$C_BOLD" "$title" "$C_RESET$C_BORDER" "$r" "$C_RESET"
}

rep_box_close() {
  local w="$1" b
  rep_repeat_v b '─' $((w - 2))
  printf '%s└%s┘%s\n' "$C_BORDER" "$b" "$C_RESET"
}

rep_box_line() {
  local w="$1" text="$2" color="${3:-$C_WHITE}" fit
  local bw=$((w - 4))
  rep_pad_v fit "$text" "$bw"
  printf '%s│%s %s%s%s %s│%s\n' "$C_BORDER" "$C_RESET" "$color" "$fit" "$C_RESET" "$C_BORDER" "$C_RESET"
}

rep_box_kv() {
  local w="$1" key="$2" val="$3" val_color="${4:-$C_WHITE}"
  local bw=$((w - 4))
  local rem=$(( bw - ${#key} - 1 ))
  local fit
  if [ "$rem" -lt 4 ]; then
    rep_box_line "$w" "$key $val" "$val_color"
    return 0
  fi
  rep_pad_v fit "$val" "$rem"
  printf '%s│%s %s%s%s %s%s%s %s│%s\n' \
    "$C_BORDER" "$C_RESET" "$C_PRIMARY" "$key" "$C_RESET" "$val_color" "$fit" "$C_RESET" "$C_BORDER" "$C_RESET"
}

rep_render_terminal() {
  local total_ph="$1" done_ph="$2" skip_ph="$3" fail_ph="$4" total_tk="$5" done_tk="$6"
  local cols="${LOOP_ENGINNER_WATCH_COLS:-${COLUMNS:-}}"
  if ! [[ "$cols" =~ ^[0-9]+$ ]]; then
    cols="$(tput cols 2>/dev/null || printf '92')"
  fi
  local w="$cols"
  [ "$w" -lt 76 ] && w=76
  [ "$w" -gt 100 ] && w=100

  local started="${META[started]:-0}" ended="${META[ended]:-$(date +%s)}" dur=0
  if [[ "$started" =~ ^[0-9]+$ ]] && [[ "$ended" =~ ^[0-9]+$ ]] && [ "$ended" -ge "$started" ]; then
    dur="$((ended - started))"
  fi

  local st="${META[status]:-unknown}"
  local badge="· $st" st_color="$C_MUTED"
  case "$st" in
    finished) badge="✓ CONCLUIDO"; st_color="$C_SUCCESS" ;;
    paused)   badge="⏸ PAUSADO"; st_color="$C_WARNING" ;;
    failed)   badge="✗ FALHOU"; st_color="$C_DANGER" ;;
  esac

  local sup_st="${RECOVERY[supervisor_state]:-desativado}"
  local retries="${RECOVERY[retries_used]:-0}/${RECOVERY[retries_limit]:-${LOOP_ENGINNER_MAX_RECOVERIES:-3}}"
  local branch="${META[branch]:-$(git -C "$REPO" branch --show-current 2>/dev/null || printf 'detached')}"
  local eff_prov="${META[provider]:-${META[engine]:-—}}"
  local model_disp="${META[model]:-—}"
  [ "$model_disp" = "—" ] && [ -n "$TOK_MODELS" ] && model_disp="$TOK_MODELS"

  echo ""
  rep_box_open "$w" "RELATORIO POS-EXECUCAO · LOOP ENGINNER"
  rep_box_kv "$w" "Status:" "$badge (supervisor: $sup_st)" "$st_color"
  rep_box_kv "$w" "Projeto:" "${META[project]:-$(basename "$REPO")} · branch: $branch · run: ${META[run]:-?}" "$C_WHITE"
  rep_box_kv "$w" "Plano:" "${META[input]:-?}" "$C_MUTED"
  rep_box_close "$w"

  rep_box_open "$w" "TEMPO & EXECUCAO"
  rep_box_kv "$w" "Janela:" "$(rep_fmt_epoch "$started") -> $(rep_fmt_epoch "$ended") (total: $(rep_fmt_duration "$dur"))" "$C_WHITE"
  rep_box_kv "$w" "Fases/Tasks:" "$done_ph/$total_ph fases ($fail_ph falharam, $skip_ph puladas) · $done_tk/$total_tk tasks" "$C_WHITE"
  rep_box_kv "$w" "Retomadas:" "$retries (ultima acao: ${RECOVERY[last_action]:-nenhuma})" "$C_CYAN"
  rep_box_close "$w"

  rep_box_open "$w" "MODELO, PROVIDER & TOKENS"
  rep_box_kv "$w" "Engine/Prov:" "${META[engine]:-—} -> efetivo: $eff_prov (cadeia: ${META[fallback_chain]:-—})" "$C_WHITE"
  rep_box_kv "$w" "Modelo/Perfil:" "$model_disp · esforco: ${META[reasoning_effort]:-—} · perfil: ${META[profile]:-—}" "$C_WHITE"
  rep_box_kv "$w" "Tokens:" "$(rep_format_tokens)" "$C_WARNING"
  if [ "${#FALLBACK_EVENTS[@]}" -gt 0 ]; then
    local fb
    for fb in "${FALLBACK_EVENTS[@]}"; do
      rep_box_kv "$w" "Fallback:" "$fb" "$C_WARNING"
    done
  fi
  rep_box_close "$w"

  rep_box_open "$w" "ENTREGAS POR FASE"
  local num pst eff_st sym lc ch cs diff_s pdur pcyc pprov pgates
  for num in "${PHASE_NUMS[@]}"; do
    pst="${PH_STATUS[$num]}"
    eff_st="$pst"
    [ "$eff_st" = "skipped" ] && [ -n "${PH_HIST_DONE[$num]:-}" ] && eff_st="done (*)"
    sym="·"; lc="$C_MUTED"
    case "$eff_st" in
      done|"done (*)") sym="✓"; lc="$C_SUCCESS" ;;
      failed)          sym="✗"; lc="$C_DANGER" ;;
      incomplete)      sym="!"; lc="$C_WARNING" ;;
      skipped)         sym="–"; lc="$C_MUTED" ;;
    esac
    rep_box_line "$w" "$sym Phase $num: ${PH_TITLE[$num]} [$eff_st]" "$lc"
    ch="${PH_COMMIT_HASH[$num]:-—}"
    cs="${PH_COMMIT_SUBJ[$num]:-}"
    diff_s="$(rep_phase_diffstat "${PH_COMMIT_HASH[$num]:-}")"
    pdur="${PH_COMMIT_DUR[$num]:-—}"
    [[ "$pdur" =~ ^[0-9]+$ ]] && pdur="$(rep_fmt_duration "$pdur")"
    pcyc="${PH_COMMIT_CYCLES[$num]:-${PH_ATTEMPT[$num]:-0}}"
    pprov="${PH_COMMIT_PROV[$num]:-$eff_prov}"
    pgates="$(rep_gate_marks "${PH_GATES[$num]:-}")"
    if [ -n "$cs" ]; then
      rep_box_line "$w" "  Commit $ch · $diff_s" "$C_MUTED"
    fi
    rep_box_line "$w" "  Duracao: $pdur · Ciclos: $pcyc · Prov: $pprov · $pgates" "$C_MUTED"
  done
  rep_box_close "$w"

  if [ "${#RETRY_EVENTS[@]}" -gt 0 ] || [ "$st" != "finished" ] || [ -n "${SESSION[last_diff_file]:-}" ]; then
    rep_box_open "$w" "RECUPERACAO & DEBUG SISTEMATICO"
    [ -n "${META[last_error]:-}" ] && rep_box_kv "$w" "Ultimo erro:" "${META[last_error]}" "$C_DANGER"
    [ -n "${SESSION[last_gate]:-}" ] && rep_box_kv "$w" "Ultimo gate:" "${SESSION[last_gate]}" "$C_WARNING"
    local rv
    for rv in "${RETRY_EVENTS[@]+"${RETRY_EVENTS[@]}"}"; do
      rep_box_line "$w" "  $rv" "$C_WHITE"
    done
    if [ -d "$RECOVERY_DIR" ]; then
      local rf
      for rf in "$RECOVERY_DIR"/*.patch "$RECOVERY_DIR"/*-lessons.md; do
        [ -e "$rf" ] || continue
        rep_box_line "$w" "  Evidencia: ${rf#"$REPO"/}" "$C_MUTED"
      done
    fi
    [ "$st" = "paused" ] && rep_box_kv "$w" "Proximo passo:" "loop-enginner resume" "$C_SUCCESS"
    rep_box_close "$w"
  fi

  printf '%sRelatorio completo salvo em:%s .loop-enginner/state/report.md\n\n' "$C_CYAN" "$C_RESET"
}

main() {
  rep_load_state
  rep_parse_tokens

  local total_ph=0 done_ph=0 skip_ph=0 fail_ph=0 total_tk=0 done_tk=0 num pst
  for num in "${PHASE_NUMS[@]}"; do
    total_ph=$((total_ph + 1))
    pst="${PH_STATUS[$num]}"
    [ "$pst" = "skipped" ] && [ -n "${PH_HIST_DONE[$num]:-}" ] && pst="done"
    case "$pst" in
      done) done_ph=$((done_ph + 1)) ;;
      skipped) skip_ph=$((skip_ph + 1)) ;;
      failed|incomplete) fail_ph=$((fail_ph + 1)) ;;
    esac
    total_tk=$((total_tk + ${PH_TASK_TOTAL[$num]:-0}))
    if [ "$pst" = "done" ]; then
      done_tk=$((done_tk + ${PH_TASK_TOTAL[$num]:-0}))
    else
      done_tk=$((done_tk + ${PH_TASK_DONE[$num]:-0}))
    fi
  done

  rep_write_markdown "$total_ph" "$done_ph" "$skip_ph" "$fail_ph" "$total_tk" "$done_tk"

  if $SAVE_ONLY; then
    return 0
  fi
  if $OUTPUT_MD; then
    cat "$REPORT_MD"
    return 0
  fi
  rep_render_terminal "$total_ph" "$done_ph" "$skip_ph" "$fail_ph" "$total_tk" "$done_tk"
}

main
