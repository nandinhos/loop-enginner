#!/usr/bin/env bash
# Contrato da Entrega B3: supervisor padrao ativo (ate 3 retomadas), trava silenciosa,
# limite recovery_required, respeito a pausa e relatorio estilizado/Markdown com tokens factuais.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) printf '%s\n' "$haystack" >&2; fail "$msg (esperado: $needle)" ;;
  esac
}

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
prompt="$(cat)"

if [ -n "${MOCK_COUNT_FILE:-}" ]; then
  c=0
  [ -f "$MOCK_COUNT_FILE" ] && c="$(cat "$MOCK_COUNT_FILE")"
  printf '%s\n' "$((c + 1))" > "$MOCK_COUNT_FILE"
fi

case "${MOCK_SCENARIO:-normal}" in
  fail_once_then_debug_ok)
    if [ ! -f "$MOCK_FLAG" ]; then
      : > "$MOCK_FLAG"
      printf 'trabalho parcial que falhou\n' > partial-s1.txt
      printf 'erro proposital tentativa 0\n'
      exit 1
    fi
    case "$prompt" in
      *"Protocolo de Debug Sistematico"*) ;;
      *) printf 'prompt sem Debug Sistematico\n' >&2; exit 2 ;;
    esac
    case "$prompt" in
      *"Context7"*) ;;
      *) printf 'prompt sem Context7\n' >&2; exit 2 ;;
    esac
    printf 'entregue apos retomada\n' > ok-s1.txt
    exit 0
    ;;
  stall_once_then_ok)
    if [ ! -f "$MOCK_FLAG" ]; then
      : > "$MOCK_FLAG"
      sleep 20
      exit 0
    fi
    printf 'recuperado de trava\n' > stall-ok.txt
    exit 0
    ;;
  always_fail)
    printf 'erro continuo %s\n' "$(date +%s)" > partial-always.txt
    printf 'falha persistente simulada\n'
    exit 1
    ;;
  pause_2_phases)
    case "$prompt" in
      *"Phase 1:"*)
        if [ -n "${MOCK_READY_FILE:-}" ]; then : > "$MOCK_READY_FILE"; fi
        sleep 2
        printf 'p1 ok\n' > p1.txt
        exit 0
        ;;
      *"Phase 2:"*)
        printf 'p2 ok\n' > p2.txt
        exit 0
        ;;
    esac
    ;;
  quota_fail)
    printf 'error: quota exceeded\n'
    exit 1
    ;;
esac
MOCK
chmod +x "$BIN/codex"

cat > "$BIN/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
is_verify=0
for arg in "$@"; do
  case "$arg" in
    Read,Glob,Grep) is_verify=1 ;;
  esac
done
if [ "$is_verify" -eq 1 ]; then
  printf 'TASK 1: DONE\n'
  exit 0
fi
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"LOOP-TASK 1 START\n"}]}}\n'
printf 'implementado pelo claude mock\n' > claude-out.txt
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"LOOP-TASK 1 DONE\n"}]}}\n'
printf '{"type":"result","subtype":"success","is_error":false,"model":"claude-sonnet-4","total_cost_usd":0.0425,"usage":{"input_tokens":1200,"cache_read_input_tokens":300,"output_tokens":450}}\n'
exit 0
MOCK
chmod +x "$BIN/claude"

cat > "$BIN/agy" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = "plan" ] || [ "$arg" = "--sandbox" ]; then
    printf 'TASK 1: DONE\n'
    exit 0
  fi
done
printf 'LOOP-TASK 1 START\n'
printf 'implementado em texto puro\n' > agy-out.txt
printf 'LOOP-TASK 1 DONE\n'
exit 0
MOCK
chmod +x "$BIN/agy"

init_repo() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "Loop Test"
  printf '%s\n' "$body" > "$dir/PHASES.md"
  git -C "$dir" add PHASES.md
  git -C "$dir" commit -qm "plano inicial"
}

# 1. Supervisor padrao ativo no run recupera falha na tentativa 0
REPO1="$TMP/repo-1"
init_repo "$REPO1" "# Plano supervisor
## Phase 1: Entrega recuperada
- [ ] Criar ok-s1.txt"

(
  cd "$REPO1"
  MOCK_SCENARIO="fail_once_then_debug_ok" \
  MOCK_FLAG="$TMP/flag-1" \
  LOOP_ENGINNER_SUPERVISOR_INTERVAL=1 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd "test -f ok-s1.txt" PHASES.md \
    > "$TMP/r1.log" 2>&1
) || { cat "$TMP/r1.log"; fail "cenario 1: supervisor nao recuperou falha unica"; }

[ -f "$REPO1/ok-s1.txt" ] || fail "cenario 1: ok-s1.txt ausente"
[ ! -e "$REPO1/partial-s1.txt" ] || fail "cenario 1: partial-s1.txt nao limpo pelo resume automatico"
grep -q $'META\tsupervisor_state\tfinished' "$REPO1/.loop-enginner/state/recovery.tsv" || fail "cenario 1: supervisor_state != finished"
grep -q $'META\tretries_used\t1' "$REPO1/.loop-enginner/state/recovery.tsv" || fail "cenario 1: retries_used != 1"
[ -f "$REPO1/.loop-enginner/state/report.md" ] || fail "cenario 1: report.md nao foi gerado"
printf 'ok: supervisor padrao ativo retoma falha com Debug Sistematico e gera report.md\n'

# 2. Deteccao de trava silenciosa + retomada automatica
REPO2="$TMP/repo-2"
init_repo "$REPO2" "# Plano trava silenciosa
## Phase 1: Destravar e entregar
- [ ] Criar stall-ok.txt"

(
  cd "$REPO2"
  MOCK_SCENARIO="stall_once_then_ok" \
  MOCK_FLAG="$TMP/flag-2" \
  LOOP_ENGINNER_SUPERVISOR_INTERVAL=1 \
  LOOP_ENGINNER_SUPERVISOR_STALL_TIMEOUT=2 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd "test -f stall-ok.txt" PHASES.md \
    > "$TMP/r2.log" 2>&1
) || { cat "$TMP/r2.log"; fail "cenario 2: supervisor nao recuperou trava silenciosa"; }

[ -f "$REPO2/stall-ok.txt" ] || fail "cenario 2: stall-ok.txt ausente"
grep -q $'META\tretries_used\t1' "$REPO2/.loop-enginner/state/recovery.tsv" || fail "cenario 2: retries_used != 1"
grep -q 'trava silenciosa' "$REPO2/.loop-enginner/state/history.tsv" || fail "cenario 2: history.tsv nao registrou trava silenciosa"
printf 'ok: supervisor detecta trava silenciosa, encerra processo e retoma com sucesso\n'

# 3. Limite de 3 tentativas esgotado -> recovery_required
REPO3="$TMP/repo-3"
init_repo "$REPO3" "# Plano limite 3
## Phase 1: Sempre falhar
- [ ] Impossivel"
COUNT3="$TMP/count3"
if (
  cd "$REPO3"
  MOCK_SCENARIO="always_fail" \
  MOCK_COUNT_FILE="$COUNT3" \
  LOOP_ENGINNER_MAX_RECOVERIES=3 \
  LOOP_ENGINNER_SUPERVISOR_INTERVAL=1 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd true PHASES.md \
    > "$TMP/r3.log" 2>&1
); then
  fail "cenario 3: deveria falhar apos esgotar 3 retomadas"
fi

[ "$(cat "$COUNT3")" = "4" ] || fail "cenario 3: esperado 4 execucoes (1 inicial + 3 retries), obteve $(cat "$COUNT3")"
grep -q $'META\tsupervisor_state\trecovery_required' "$REPO3/.loop-enginner/state/recovery.tsv" \
  || fail "cenario 3: recovery.tsv sem recovery_required"
grep -q $'META\tretries_used\t3' "$REPO3/.loop-enginner/state/recovery.tsv" \
  || fail "cenario 3: retries_used != 3"
[ -f "$REPO3/.loop-enginner/state/report.md" ] || fail "cenario 3: report.md ausente apos recovery_required"
printf 'ok: limite de 3 retomadas encerra fail-closed com recovery_required\n'

# 4. Pausa graciosa respeitada pelo supervisor (nao reinicia sozinho)
REPO4="$TMP/repo-4"
init_repo "$REPO4" "# Plano pausa sob supervisor
## Phase 1: Etapa 1
- [ ] Criar p1.txt

## Phase 2: Etapa 2
- [ ] Criar p2.txt"
READY4="$TMP/ready4"
(
  cd "$REPO4"
  MOCK_SCENARIO="pause_2_phases" \
  MOCK_READY_FILE="$READY4" \
  LOOP_ENGINNER_SUPERVISOR_INTERVAL=1 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/r4.log" 2>&1
) &
RUN4_PID=$!

for _ in $(seq 1 40); do
  [ -f "$READY4" ] && break
  sleep 0.1
done
[ -f "$READY4" ] || { kill "$RUN4_PID" 2>/dev/null || true; fail "cenario 4: mock lento nao iniciou"; }

bash "$CLI" pause --target "$REPO4" > /dev/null 2>&1 || fail "cenario 4: pause falhou"
wait "$RUN4_PID" || fail "cenario 4: supervisor deveria sair 0 quando pausado"

grep -q $'META\tsupervisor_state\tpaused' "$REPO4/.loop-enginner/state/recovery.tsv" \
  || fail "cenario 4: recovery.tsv sem supervisor_state=paused"
grep -q $'META\tretries_used\t0' "$REPO4/.loop-enginner/state/recovery.tsv" \
  || fail "cenario 4: retries_used deveria permanecer 0 em pausa"
[ -f "$REPO4/p1.txt" ] || fail "cenario 4: p1.txt nao foi commitado"
[ ! -e "$REPO4/p2.txt" ] || fail "cenario 4: Phase 2 nao deveria rodar apos pausa"
printf 'ok: supervisor respeita status paused sem retomar automaticamente\n'

# 5. Relatorio pos-conclusao: tokens reais do claude vs n/d (modo text) + fallback
REPO5A="$TMP/repo-5a"
init_repo "$REPO5A" "# Plano claude tokens
## Phase 1: Entrega claude
- [ ] Criar claude-out.txt"
(
  cd "$REPO5A"
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine claude --test-cmd "test -f claude-out.txt" PHASES.md \
    > "$TMP/r5a.log" 2>&1
) || { cat "$TMP/r5a.log"; fail "cenario 5a falhou"; }

rep_5a="$(bash "$CLI" report --target "$REPO5A" --no-color)"
rep_5a_md="$(bash "$CLI" report --target "$REPO5A" --md)"
assert_contains "$rep_5a" "RELATORIO POS-EXECUCAO" "5a: cabecalho do relatorio ausente"
assert_contains "$rep_5a" "in=1200" "5a: input_tokens ausente no relatorio"
assert_contains "$rep_5a" "out=450" "5a: output_tokens ausente no relatorio"
assert_contains "$rep_5a" "total=1650" "5a: total tokens ausente no relatorio"
assert_contains "$rep_5a" "cache_read=300" "5a: cache_read_input_tokens ausente"
assert_contains "$rep_5a" "claude-sonnet-4" "5a: modelo observado ausente"
assert_contains "$rep_5a" "file changed" "5a: diffstat do commit ausente"
assert_contains "$rep_5a_md" "| Fase | Titulo |" "5a: tabela Markdown ausente em --md"

REPO5B="$TMP/repo-5b"
init_repo "$REPO5B" "# Plano agy texto com fallback
## Phase 1: Entrega via fallback agy
- [ ] Criar agy-out.txt"
(
  cd "$REPO5B"
  MOCK_SCENARIO="quota_fail" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine codex --test-cmd "test -f agy-out.txt" PHASES.md \
    > "$TMP/r5b.log" 2>&1
) || { cat "$TMP/r5b.log"; fail "cenario 5b falhou"; }

rep_5b="$(bash "$CLI" report --target "$REPO5B" --no-color)"
assert_contains "$rep_5b" "n/d (modo text" "5b: deveria declarar tokens n/d (modo text) quando ausentes no log"
assert_contains "$rep_5b" "efetivo: agy" "5b: provider efetivo agy ausente"
assert_contains "$rep_5b" "codex -> agy" "5b: transicao de fallback ausente no relatorio"
printf 'ok: relatorio pos-conclusao exibe tempo, commits, diffstat, fallback e tokens factuais\n'
