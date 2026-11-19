#!/usr/bin/env bash
# Testes do comando 'loop-enginner config' e integracao com run/status.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert() { "$@" >/dev/null 2>&1 || fail "assert falhou: $*"; }
assert_not() { ! "$@" >/dev/null 2>&1 || fail "assert_not falhou: $*"; }

mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Loop Test"
printf 'base\n' > "$REPO/base.txt"
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm "base"

bash "$CLI" install --target "$REPO" >/dev/null

# 1. loop-enginner config gera .loop-enginner/config.env com os parametros
bash "$CLI" config --target "$REPO" \
  --engine agy \
  --model gemini-3.8-flash-high \
  --effort high \
  --fallback-chain "agy opencode" \
  --test-cmd "bash test.sh" >/dev/null

CFG="$REPO/.loop-enginner/config.env"
assert test -f "$CFG"
assert grep -q 'LOOP_ENGINNER_ENGINE="agy"' "$CFG"
assert grep -q 'LOOP_ENGINNER_AGY_MODEL="gemini-3.8-flash-high"' "$CFG"
assert grep -q 'LOOP_ENGINNER_AGY_EFFORT="high"' "$CFG"
assert grep -q 'LOOP_ENGINNER_FALLBACK_CHAIN="agy opencode"' "$CFG"
assert grep -q 'LOOP_ENGINNER_TEST_CMD="bash test.sh"' "$CFG"
printf 'ok: config grava .loop-enginner/config.env com variaveis esperadas\n'

# 2. loop-enginner status reflete a configuracao persistida
status_out="$(bash "$CLI" status --target "$REPO")"
assert grep -q 'config:   engine=agy modelo=gemini-3.8-flash-high esforço=high fallback=agy opencode' <<< "$status_out"
printf 'ok: status exibe configuracao persistida\n'

# 3. loop-enginner run carrega o config.env automaticamente sem flags de CLI
BIN_MOCK="$TMP/bin"
mkdir -p "$BIN_MOCK"
cat > "$BIN_MOCK/agy" <<'EOF'
#!/usr/bin/env bash
# Mock do agy capturando parametros recebidos
printf 'MOCK_AGY: args=%s\n' "$*" >> "$MOCK_LOG"
printf 'ok\n'
exit 0
EOF
chmod +x "$BIN_MOCK/agy"

cat > "$REPO/.loop-enginner/PHASES.md" <<'EOF'
# Test Phases

## Phase 1: Test Phase Config
- [ ] Implementar algo
EOF

export MOCK_LOG="$TMP/mock_agy.log"
PATH="$BIN_MOCK:$PATH" bash "$CLI" run --target "$REPO" --no-supervise --no-verify >/dev/null 2>&1 || true

assert test -f "$MOCK_LOG"
mock_content="$(cat "$MOCK_LOG")"
assert grep -q -- '--model gemini-3.8-flash-high' <<< "$mock_content"
assert grep -q -- '--effort high' <<< "$mock_content"
printf 'ok: run carrega config.env e repassa modelo/esforco ao provider\n'

# 4. CLI flags tem precedencia sobre config.env
rm -f "$MOCK_LOG"
PATH="$BIN_MOCK:$PATH" bash "$CLI" run --target "$REPO" --no-supervise --no-verify \
  --model "gemini-3.8-flash-low" --effort "low" >/dev/null 2>&1 || true

assert test -f "$MOCK_LOG"
mock_content="$(cat "$MOCK_LOG")"
assert grep -q -- '--model gemini-3.8-flash-low' <<< "$mock_content"
assert grep -q -- '--effort low' <<< "$mock_content"
printf 'ok: flags de CLI sobrepoem modelo e esforco do config.env\n'

# 5. uninstall preserva config.env por padrao, --purge remove
bash "$CLI" uninstall --target "$REPO" >/dev/null
assert test -f "$CFG"
bash "$CLI" uninstall --target "$REPO" --purge >/dev/null
assert_not test -f "$CFG"
printf 'ok: uninstall preserva config.env e --purge remove\n'
