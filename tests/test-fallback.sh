#!/usr/bin/env bash
# Contrato da cadeia de fallback configuravel (Fase A3), 100% com mocks no PATH.
# Prova: troca por gatilho + sticky + painel/status, guarda negativa (exit 0),
# travamento sem progresso por provider (streaming vs batch), modo auto vs fail-closed,
# cadeia esgotada e erro normal sem disparo de fallback.
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
cat >/dev/null || true

if [ -n "${MOCK_CODEX_COUNT_FILE:-}" ]; then
  c=0
  [ -f "$MOCK_CODEX_COUNT_FILE" ] && c="$(cat "$MOCK_CODEX_COUNT_FILE")"
  printf '%s\n' "$((c + 1))" > "$MOCK_CODEX_COUNT_FILE"
fi

case "${MOCK_CODEX_MODE:-quota_fail}" in
  quota_fail)
    printf 'error: quota exceeded for current billing period\n'
    exit 1
    ;;
  unauthorized_fail)
    printf 'error: unauthorized API key\n'
    exit 1
    ;;
  service_fail)
    printf 'error: service unavailable\n'
    exit 1
    ;;
  normal_error)
    printf 'syntax error in app.js line 10\n'
    exit 1
    ;;
  success_with_quota_text)
    printf 'LOOP-TASK 1 START\n'
    printf 'rate limit reached\n'
    printf 'quota exceeded\n'
    printf 'unauthorized\n'
    printf 'service unavailable\n'
    printf 'criado apesar do texto de gatilho no log\n' > "${MOCK_TARGET_FILE:-neg-feature.txt}"
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  stall)
    sleep 20
    exit 0
    ;;
  *)
    printf 'modo codex mock desconhecido: %s\n' "${MOCK_CODEX_MODE:-}" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$BIN/codex"

cat > "$BIN/agy" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${MOCK_AGY_CALLED_FILE:-}" ]; then
  : > "$MOCK_AGY_CALLED_FILE"
fi

is_verify=0
for arg in "$@"; do
  if [ "$arg" = "plan" ] || [ "$arg" = "--sandbox" ]; then
    is_verify=1
    break
  fi
done

if [ "$is_verify" -eq 1 ]; then
  printf 'TASK 1: DONE\n'
  exit 0
fi

case "${MOCK_AGY_MODE:-ok}" in
  ok)
    printf 'LOOP-TASK 1 START\n'
    printf 'implementado pelo fallback agy\n' > "${MOCK_TARGET_FILE:-fb-feature.txt}"
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  batch_sleep_ok)
    sleep 3
    printf 'LOOP-TASK 1 START\n'
    printf 'implementado em batch pelo agy\n' > "${MOCK_TARGET_FILE:-stall-feature.txt}"
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  service_fail)
    printf 'error: service unavailable\n'
    exit 1
    ;;
  *)
    printf 'modo agy mock desconhecido: %s\n' "${MOCK_AGY_MODE:-}" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$BIN/agy"

cat > "$BIN/opencode" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null || true

if [ -n "${MOCK_OPENCODE_CALLED_FILE:-}" ]; then
  : > "$MOCK_OPENCODE_CALLED_FILE"
fi

prev=""
for arg in "$@"; do
  if [ "$prev" = "--agent" ] && [ "$arg" = "plan" ]; then
    printf 'TASK 1: DONE\n'
    exit 0
  fi
  prev="$arg"
done

printf 'LOOP-TASK 1 START\n'
printf 'implementado pelo fallback opencode\n' > "${MOCK_TARGET_FILE:-auto-feature.txt}"
printf 'LOOP-TASK 1 DONE\n'
exit 0
MOCK
chmod +x "$BIN/opencode"

init_repo() {
  local dir="$1" task_text="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "Loop Test"
  cat > "$dir/PHASES.md" <<EOF
# Plano de teste fallback

## Phase 1: Entrega com resiliencia

- [ ] $task_text
EOF
  git -C "$dir" add PHASES.md
  git -C "$dir" commit -qm "plano inicial"
}

# 1. Troca de provider por gatilho de quota + sticky + painel/status + hook
REPO1="$TMP/repo-1"
init_repo "$REPO1" "Criar fb-feature.txt via fallback"
CODEX_COUNT="$TMP/codex-count-1.txt"
cat > "$TMP/hook-1.sh" <<HOOK
#!/usr/bin/env bash
if [ "\${1:-}" = "provider_fallback" ]; then
  printf '%s\n' "\${2:-}" > "$TMP/hook-fb-detail.txt"
fi
HOOK
chmod +x "$TMP/hook-1.sh"

(
  cd "$REPO1"
  MOCK_CODEX_MODE="quota_fail" \
  MOCK_CODEX_COUNT_FILE="$CODEX_COUNT" \
  MOCK_AGY_MODE="ok" \
  MOCK_TARGET_FILE="fb-feature.txt" \
  LOOP_ENGINNER_HOOK="$TMP/hook-1.sh" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --test-cmd "test -f fb-feature.txt" PHASES.md \
    > "$TMP/run-1.log" 2>&1
) || { cat "$TMP/run-1.log"; fail "cenario 1 (codex -> agy) falhou"; }

[ -f "$REPO1/fb-feature.txt" ] || fail "cenario 1: fb-feature.txt ausente"
[ "$(cat "$CODEX_COUNT")" = "1" ] || fail "cenario 1: codex deveria rodar 1 vez (sticky), rodou $(cat "$CODEX_COUNT")"
grep -q $'META\tengine\tcodex' "$REPO1/.loop-enginner/state/run.tsv" || fail "cenario 1: engine != codex"
grep -q $'META\tprovider\tagy' "$REPO1/.loop-enginner/state/run.tsv" || fail "cenario 1: provider != agy"
grep -q 'codex -> agy' "$TMP/hook-fb-detail.txt" || fail "cenario 1: hook provider_fallback nao registrado"

watch_out="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=50 \
  bash "$ROOT/lib/loop-watch.sh" --once --no-color "$REPO1" 2>/dev/null)" \
  || fail "cenario 1: loop-watch --once falhou"
case "$watch_out" in
  *'Engine: codex'*) ;;
  *) fail "cenario 1: painel sem Engine: codex" ;;
esac
case "$watch_out" in
  *'Provider: agy'*) ;;
  *) fail "cenario 1: painel sem Provider: agy" ;;
esac

status_out="$(PATH="$BIN:/usr/bin:/bin" bash "$CLI" status --target "$REPO1" 2>&1)" \
  || fail "cenario 1: status falhou"
case "$status_out" in
  *'engine=codex provider=agy'*) ;;
  *) fail "cenario 1: status nao mostrou engine=codex provider=agy: $status_out" ;;
esac
printf 'ok: troca por gatilho de quota (codex -> agy), sticky, hook, painel e status\n'

# 2. Teste negativo: texto de gatilho no log com sucesso (exit 0) NAO dispara fallback
REPO2="$TMP/repo-2"
init_repo "$REPO2" "Criar neg-feature.txt com exit 0"
AGY_CALLED_NEG="$TMP/agy-called-neg"
(
  cd "$REPO2"
  MOCK_CODEX_MODE="success_with_quota_text" \
  MOCK_AGY_CALLED_FILE="$AGY_CALLED_NEG" \
  MOCK_TARGET_FILE="neg-feature.txt" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --no-verify --test-cmd "test -f neg-feature.txt" PHASES.md \
    > "$TMP/run-2.log" 2>&1
) || { cat "$TMP/run-2.log"; fail "cenario 2 (teste negativo) falhou"; }

[ ! -e "$AGY_CALLED_NEG" ] || fail "cenario 2: agy foi acionado mesmo com exit 0 do codex"
[ -f "$REPO2/neg-feature.txt" ] || fail "cenario 2: neg-feature.txt nao foi criado"
grep -q $'META\tprovider\tcodex' "$REPO2/.loop-enginner/state/run.tsv" || fail "cenario 2: provider nao permaneceu codex"
printf 'ok: teste negativo (texto de gatilho com exit 0 nao dispara fallback)\n'

# 3. Travamento sem progresso com timeout por provider (batch agy sobrevive ao limite do codex)
REPO3="$TMP/repo-3"
init_repo "$REPO3" "Criar stall-feature.txt apos timeout do codex"
(
  cd "$REPO3"
  MOCK_CODEX_MODE="stall" \
  MOCK_AGY_MODE="batch_sleep_ok" \
  MOCK_TARGET_FILE="stall-feature.txt" \
  LOOP_ENGINNER_WATCHDOG_POLL=1 \
  LOOP_ENGINNER_CODEX_INACTIVITY_TIMEOUT=2 \
  LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT=10 \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --no-verify --test-cmd "test -f stall-feature.txt" PHASES.md \
    > "$TMP/run-3.log" 2>&1
) || { cat "$TMP/run-3.log"; fail "cenario 3 (vigia por provider) falhou"; }

[ -f "$REPO3/stall-feature.txt" ] || fail "cenario 3: stall-feature.txt nao foi criado"
grep -q $'META\tengine\tcodex' "$REPO3/.loop-enginner/state/run.tsv" || fail "cenario 3: engine != codex"
grep -q $'META\tprovider\tagy' "$REPO3/.loop-enginner/state/run.tsv" || fail "cenario 3: provider != agy"
printf 'ok: vigia de inatividade por provider mata codex travado e preserva agy batch\n'

# 4. Modo auto (detecta instalados em runtime) vs cadeia explicita fail-closed
BIN_AUTO="$TMP/bin-auto"
mkdir -p "$BIN_AUTO"
ln -s "$BIN/codex" "$BIN_AUTO/codex"
ln -s "$BIN/opencode" "$BIN_AUTO/opencode"

REPO4="$TMP/repo-4"
init_repo "$REPO4" "Criar auto-feature.txt via auto discovery"
(
  cd "$REPO4"
  MOCK_CODEX_MODE="unauthorized_fail" \
  MOCK_TARGET_FILE="auto-feature.txt" \
  LOOP_ENGINNER_AGY_BIN="/nonexistent/agy" \
  LOOP_ENGINNER_FALLBACK_CHAIN="auto" \
  PATH="$BIN_AUTO:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --no-verify --test-cmd "test -f auto-feature.txt" PHASES.md \
    > "$TMP/run-4.log" 2>&1
) || { cat "$TMP/run-4.log"; fail "cenario 4a (modo auto) falhou"; }

[ -f "$REPO4/auto-feature.txt" ] || fail "cenario 4a: auto-feature.txt ausente"
grep -q $'META\tprovider\topencode' "$REPO4/.loop-enginner/state/run.tsv" || fail "cenario 4a: provider != opencode"

REPO4B="$TMP/repo-4b"
init_repo "$REPO4B" "Falhar fail-closed no preflight"
if (
  cd "$REPO4B"
  LOOP_ENGINNER_AGY_BIN="/nonexistent/agy" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN_AUTO:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --no-verify --test-cmd true PHASES.md > "$TMP/run-4b.log" 2>&1
); then
  fail "cenario 4b: cadeia explicita com degrau ausente deveria falhar no preflight"
fi
printf 'ok: modo auto detecta instalados e cadeia explicita falha alto (fail-closed)\n'

# 5. Cadeia esgotada e erro comum nao-fallback
REPO5A="$TMP/repo-5a"
init_repo "$REPO5A" "Esgotar cadeia quando todos falham"
if (
  cd "$REPO5A"
  MOCK_CODEX_MODE="service_fail" \
  MOCK_AGY_MODE="service_fail" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd true PHASES.md \
    > "$TMP/run-5a.log" 2>&1
); then
  fail "cenario 5a: cadeia esgotada deveria retornar != 0"
fi
case "$(git -C "$REPO5A" log -1 --pretty=%s)" in
  "feat(phase-1):"*) fail "cenario 5a: criou commit feat com cadeia esgotada" ;;
esac

REPO5B="$TMP/repo-5b"
init_repo "$REPO5B" "Nao escalar em erro comum de codigo"
AGY_CALLED_5B="$TMP/agy-called-5b"
if (
  cd "$REPO5B"
  MOCK_CODEX_MODE="normal_error" \
  MOCK_AGY_CALLED_FILE="$AGY_CALLED_5B" \
  LOOP_ENGINNER_FALLBACK_CHAIN="codex agy" \
  PATH="$BIN:/usr/bin:/bin" \
    bash "$CLI" run --engine codex --max-cycles 1 --no-verify --test-cmd true PHASES.md \
    > "$TMP/run-5b.log" 2>&1
); then
  fail "cenario 5b: erro comum deveria retornar != 0"
fi
[ ! -e "$AGY_CALLED_5B" ] || fail "cenario 5b: erro comum sem gatilho disparou fallback para agy"
grep -q $'META\tprovider\tcodex' "$REPO5B/.loop-enginner/state/run.tsv" || fail "cenario 5b: provider mudou sem gatilho"
printf 'ok: cadeia esgotada aborta sem commit e erro comum nao dispara fallback\n'
