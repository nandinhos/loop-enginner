#!/usr/bin/env bash
# Contrato da Entrega B2: debug sistematico (Context7 + memoria nao bloqueante),
# retomada segura em arvore suja, lock de concorrencia, pausa graciosa e SIGTERM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
prompt="$(cat)"

if [ -n "${MOCK_PROMPT_LOG_DIR:-}" ]; then
  mkdir -p "$MOCK_PROMPT_LOG_DIR"
  c=1
  while [ -e "$MOCK_PROMPT_LOG_DIR/prompt-$c.txt" ]; do c=$((c + 1)); done
  printf '%s' "$prompt" > "$MOCK_PROMPT_LOG_DIR/prompt-$c.txt"
fi

case "$prompt" in
  *"Phase 1:"*) phase=1 ;;
  *"Phase 2:"*) phase=2 ;;
  *) phase=1 ;;
esac

# Em cenario lento, sinaliza inicio e espera breve antes de concluir
if [ "${MOCK_SLOW_PHASE:-0}" = "$phase" ]; then
  if [ -n "${MOCK_READY_FILE:-}" ]; then : > "$MOCK_READY_FILE"; fi
  sleep "${MOCK_SLOW_SECS:-2}"
fi

if [ "$phase" = "1" ]; then
  case "${MOCK_P1_MODE:-ok}" in
    ok)
      printf 'phase 1 done\n' > p1.txt
      exit 0
      ;;
    fail_with_pause_flag)
      printf 'dirty from failed cycle\n' > partial-p1.txt
      mkdir -p .loop-enginner/state
      printf '1\n' > .loop-enginner/state/pause.request
      printf 'MOCK_FAIL_TEST\n' > .mock-fail
      exit 0
      ;;
    pause_or_resume_ok)
      rm -f .mock-fail
      printf 'phase 1 clean ok\n' > p1.txt
      exit 0
      ;;
  esac
fi

if [ "$phase" = "2" ]; then
  if [ -n "${MOCK_P2_FAIL_ONCE_FLAG:-}" ] && [ ! -f "$MOCK_P2_FAIL_ONCE_FLAG" ]; then
    : > "$MOCK_P2_FAIL_ONCE_FLAG"
    printf 'mutacao rastreada\n' >> base.txt
    printf 'arquivo novo parcial da fase 2\n' > partial-p2.txt
    printf 'erro de teste simulado na fase 2\n'
    exit 0
  fi
  rm -f partial-p2.txt
  printf 'fase 2 concluida corretamente\n' > p2.txt
  exit 0
fi
MOCK
chmod +x "$BIN/codex"

init_repo() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "Loop Test"
  printf 'base original\n' > "$dir/base.txt"
  printf '%s\n' "$body" > "$dir/PHASES.md"
  git -C "$dir" add base.txt PHASES.md
  git -C "$dir" commit -qm "commit inicial"
}

# 1. Retomada segura apos fase incompleta deixar arvore suja + Debug Sistematico
REPO1="$TMP/repo-resume"
init_repo "$REPO1" "# Plano 2 fases

## Phase 1: Entrega base

- [ ] Criar p1.txt

## Phase 2: Entrega com falha recuperavel

- [ ] Criar p2.txt"

FAIL_ONCE_1="$TMP/p2-failed-once"
PROMPTS1="$TMP/prompts-1"
if (
  cd "$REPO1"
  MOCK_P2_FAIL_ONCE_FLAG="$FAIL_ONCE_1" \
  MOCK_PROMPT_LOG_DIR="$PROMPTS1" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --no-supervise --engine codex --max-cycles 1 --no-verify \
      --test-cmd 'bash -c "if [ -f partial-p2.txt ]; then echo teste falhou por parcial; exit 1; fi; test -f p1.txt"' \
      PHASES.md > "$TMP/run1-fail.log" 2>&1
); then
  fail "cenario 1: Fase 2 deveria ter falhado no ciclo 1"
fi

[ -f "$REPO1/p1.txt" ] || fail "cenario 1: commit da Fase 1 ausente"
[ -f "$REPO1/partial-p2.txt" ] || fail "cenario 1: partial-p2.txt deveria permanecer na arvore suja apos falha"
[ -n "$(git -C "$REPO1" status --porcelain)" ] || fail "cenario 1: arvore deveria estar suja antes do resume"

(
  cd "$REPO1"
  MOCK_P2_FAIL_ONCE_FLAG="$FAIL_ONCE_1" \
  MOCK_PROMPT_LOG_DIR="$PROMPTS1" \
  PATH="$BIN:$PATH" \
    bash "$CLI" resume > "$TMP/run1-resume.log" 2>&1
) || { cat "$TMP/run1-resume.log"; fail "cenario 1: resume falhou"; }

[ -f "$REPO1/p2.txt" ] || fail "cenario 1: p2.txt ausente apos resume"
[ ! -e "$REPO1/partial-p2.txt" ] || fail "cenario 1: partial-p2.txt nao foi limpo no resume"
grep -qxF 'base original' "$REPO1/base.txt" || fail "cenario 1: mutacao em base.txt nao foi restaurada"
[ -z "$(git -C "$REPO1" status --porcelain)" ] || fail "cenario 1: arvore nao terminou limpa apos resume"

patch_cnt="$(find "$REPO1/.loop-enginner/state/recovery" -name 'phase-02-*.patch' | wc -l)"
[ "$patch_cnt" -ge 1 ] || fail "cenario 1: patch de recuperacao nao foi arquivado"
[ -f "$REPO1/.loop-enginner/state/recovery/phase-02-lessons.md" ] || fail "cenario 1: licoes locais nao foram gravadas"

# Prompt usado na retomada (ultimo prompt) deve trazer Debug Sistematico + Context7 + memoria opcional
last_prompt=""
for f in "$PROMPTS1"/prompt-*.txt; do
  [ -f "$f" ] || continue
  if [ -z "$last_prompt" ] || [ "$f" -nt "$last_prompt" ]; then
    last_prompt="$f"
  fi
done
[ -n "$last_prompt" ] || fail "cenario 1: nenhum prompt registrado"
grep -q 'Protocolo de Debug Sistematico' "$last_prompt" || fail "cenario 1: prompt sem Debug Sistematico"
grep -q 'Context7' "$last_prompt" || fail "cenario 1: prompt sem orientacao Context7"
grep -qi 'NAO bloqueante' "$last_prompt" || fail "cenario 1: prompt sem clausula de memoria opcional/nao bloqueante"
grep -q 'teste falhou por parcial' "$last_prompt" || fail "cenario 1: prompt sem causa da falha anterior"
printf 'ok: resume arquiva patch, limpa fase incompleta, preserva Phase 1 e injeta Debug Sistematico\n'

# 2. Fail-closed em arvore suja sem sessao e com HEAD divergente
REPO2A="$TMP/repo-noclean-nosess"
init_repo "$REPO2A" "# Plano
## Phase 1: Teste
- [ ] Algo"
printf 'edicao manual do usuario\n' > "$REPO2A/user.txt"
if (
  cd "$REPO2A"
  PATH="$BIN:$PATH" bash "$CLI" resume --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/r2a.log" 2>&1
); then
  fail "cenario 2a: resume aceitou arvore suja sem session.tsv"
fi
[ -f "$REPO2A/user.txt" ] || fail "cenario 2a: user.txt manual foi removido!"

# 2b: HEAD != base_head
REPO2B="$TMP/repo-diverged"
init_repo "$REPO2B" "# Plano
## Phase 1: Divergir
- [ ] Falhar"
if (
  cd "$REPO2B"
  MOCK_P1_MODE="fail_with_pause_flag" PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd false PHASES.md > /dev/null 2>&1
); then
  :
fi
# Commita manualmente fora do loop mantendo algo sujo depois
printf 'manual\n' > "$REPO2B/manual.txt"
git -C "$REPO2B" add manual.txt
git -C "$REPO2B" commit -qm "commit manual externo"
printf 'alteracao nova suja\n' > "$REPO2B/dirty2.txt"
if (
  cd "$REPO2B"
  PATH="$BIN:$PATH" bash "$CLI" resume > "$TMP/r2b.log" 2>&1
); then
  fail "cenario 2b: resume aceitou arvore suja com HEAD != base_head"
fi
[ -f "$REPO2B/dirty2.txt" ] || fail "cenario 2b: dirty2.txt foi apagado apesar de fail-closed!"
printf 'ok: resume fail-closed sem session.tsv ou com HEAD divergente (arquivos preservados)\n'

# 3. Lock de concorrencia bloqueia segunda instancia enquanto PID vive
REPO3="$TMP/repo-lock"
init_repo "$REPO3" "# Plano
## Phase 1: Lock
- [ ] Fazer"
mkdir -p "$REPO3/.loop-enginner/state"
sleep 30 &
LOCK_HOLDER=$!
printf '%s\t%s\n' "$LOCK_HOLDER" "$(date +%s)" > "$REPO3/.loop-enginner/state/run.lock"
if (
  cd "$REPO3"
  PATH="$BIN:$PATH" bash "$CLI" run --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/r3.log" 2>&1
); then
  kill "$LOCK_HOLDER" 2>/dev/null || true
  fail "cenario 3: segundo run ignorou run.lock ativo"
fi
kill "$LOCK_HOLDER" 2>/dev/null || true
wait "$LOCK_HOLDER" 2>/dev/null || true
grep -q "PID $LOCK_HOLDER" "$TMP/r3.log" || fail "cenario 3: mensagem nao citou PID dono do lock"
printf 'ok: lock de concorrencia bloqueia run paralelo enquanto processo estiver vivo\n'

# 4. Pausa graciosa durante Phase 1 finaliza Phase 1 e para antes da Phase 2; resume conclui Phase 2
REPO4="$TMP/repo-pause-clean"
init_repo "$REPO4" "# Plano pausa
## Phase 1: Primeira etapa
- [ ] Criar p1.txt

## Phase 2: Segunda etapa
- [ ] Criar p2.txt"

READY4="$TMP/ready4"
(
  cd "$REPO4"
  MOCK_SLOW_PHASE=1 \
  MOCK_SLOW_SECS=2 \
  MOCK_READY_FILE="$READY4" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/r4.log" 2>&1
) &
RUN4_PID=$!

for _ in $(seq 1 40); do
  [ -f "$READY4" ] && break
  sleep 0.1
done
[ -f "$READY4" ] || { kill "$RUN4_PID" 2>/dev/null || true; fail "cenario 4: mock lento nao iniciou"; }

bash "$CLI" pause --target "$REPO4" > "$TMP/pause4.log" 2>&1 || { cat "$TMP/pause4.log"; fail "cenario 4: comando pause falhou"; }
wait "$RUN4_PID" || fail "cenario 4: run pausado deveria sair com exit 0"

[ -f "$REPO4/p1.txt" ] || fail "cenario 4: Phase 1 nao foi concluida antes da pausa"
[ ! -e "$REPO4/p2.txt" ] || fail "cenario 4: Phase 2 nao deveria iniciar apos pedido de pausa"
grep -q $'META\tstatus\tpaused' "$REPO4/.loop-enginner/state/run.tsv" || fail "cenario 4: status nao ficou paused"

watch_p="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=40 bash "$ROOT/lib/loop-watch.sh" --once --no-color "$REPO4" 2>/dev/null)"
case "$watch_p" in
  *'Pausado'*) ;;
  *) fail "cenario 4: painel nao exibiu status Pausado" ;;
esac

(
  cd "$REPO4"
  PATH="$BIN:$PATH" bash "$CLI" resume > "$TMP/r4-resume.log" 2>&1
) || { cat "$TMP/r4-resume.log"; fail "cenario 4: resume apos pausa falhou"; }
[ -f "$REPO4/p2.txt" ] || fail "cenario 4: Phase 2 nao concluida apos resume"
grep -q $'META\tstatus\tfinished' "$REPO4/.loop-enginner/state/run.tsv" || fail "cenario 4: status final != finished"
printf 'ok: pausa graciosa finaliza fase aberta, grava status=paused e resume conclui restante\n'

# 5. Pausa apos ciclo vermelho evita gastar ciclos extras e resume limpa fase incompleta
REPO5="$TMP/repo-pause-red"
init_repo "$REPO5" "# Plano pausa vermelho
## Phase 1: Falha no ciclo 1 e pausa
- [ ] Criar p1.txt"

COUNT5="$TMP/count5"
(
  cd "$REPO5"
  MOCK_P1_MODE="fail_with_pause_flag" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --max-cycles 3 --no-verify \
      --test-cmd 'bash -c "c=0; [ -f \"'"$COUNT5"'\" ] && c=\$(cat \"'"$COUNT5"'\"); echo \$((c+1)) > \"'"$COUNT5"'\"; [ ! -f .mock-fail ]"' \
      PHASES.md > "$TMP/r5.log" 2>&1
) || { cat "$TMP/r5.log"; fail "cenario 5: pausa em ciclo vermelho deveria sair exit 0"; }

[ "$(cat "$COUNT5")" = "1" ] || fail "cenario 5: gastou mais de 1 ciclo apesar de pausa solicitada"
grep -q $'META\tstatus\tpaused' "$REPO5/.loop-enginner/state/run.tsv" || fail "cenario 5: run.tsv sem paused"

(
  cd "$REPO5"
  MOCK_P1_MODE="pause_or_resume_ok" \
  PATH="$BIN:$PATH" \
    bash "$CLI" resume > "$TMP/r5-resume.log" 2>&1
) || { cat "$TMP/r5-resume.log"; fail "cenario 5: resume apos pausa vermelha falhou"; }
[ -f "$REPO5/p1.txt" ] || fail "cenario 5: p1.txt ausente apos resume"
[ ! -e "$REPO5/partial-p1.txt" ] || fail "cenario 5: partial-p1.txt nao limpo no resume"
printf 'ok: pausa apos ciclo vermelho interrompe ciclos e resume retoma limpo\n'

# 6. SIGTERM com watchdog ativo remove run.lock e nao deixa .pid orfao
REPO6="$TMP/repo-sigterm"
WDTMP="$TMP/wdtmp"
mkdir -p "$WDTMP"
init_repo "$REPO6" "# Plano SIGTERM
## Phase 1: Lento com watchdog
- [ ] Esperar"

READY6="$TMP/ready6"
(
  cd "$REPO6"
  TMPDIR="$WDTMP" \
  MOCK_SLOW_PHASE=1 \
  MOCK_SLOW_SECS=20 \
  MOCK_READY_FILE="$READY6" \
  LOOP_ENGINNER_WATCHDOG_POLL=1 \
  LOOP_ENGINNER_CODEX_INACTIVITY_TIMEOUT=20 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --no-supervise --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/r6.log" 2>&1
) &
RUN6_PID=$!

for _ in $(seq 1 40); do
  [ -f "$READY6" ] && [ -f "$REPO6/.loop-enginner/state/run.lock" ] && break
  sleep 0.1
done
[ -f "$READY6" ] || { kill "$RUN6_PID" 2>/dev/null || true; fail "cenario 6: mock com watchdog nao iniciou"; }

LOOP6_PID="$(cut -f1 "$REPO6/.loop-enginner/state/run.lock")"
kill -TERM "$LOOP6_PID"
wait "$RUN6_PID" 2>/dev/null || true

[ ! -e "$REPO6/.loop-enginner/state/run.lock" ] || fail "cenario 6: run.lock sobrou apos SIGTERM"
pid_leftovers="$(find "$WDTMP" -name '*.pid' | wc -l)"
[ "$pid_leftovers" -eq 0 ] || fail "cenario 6: sobraram $pid_leftovers arquivos .pid orfaos em $WDTMP"
printf 'ok: SIGTERM com watchdog ativo encerra rapido e limpa run.lock e .pid temporarios\n'
