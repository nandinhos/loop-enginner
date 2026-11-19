#!/usr/bin/env bash
# Contrato do adapter Antigravity (agy) com mock no PATH (nunca chama agy real).
# Prova: impl + verify read-only, timeout por provider, doctor/status, gate 0 e guarda de exit code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/agy" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

mode="${MOCK_AGY_MODE:-normal}"
is_verify=0
for arg in "$@"; do
  if [ "$arg" = "plan" ] || [ "$arg" = "--sandbox" ]; then
    is_verify=1
    break
  fi
done

record_args() {
  local out="$1"
  shift
  : > "$out"
  local a
  for a in "$@"; do
    case "$a" in
      --print=*) printf '%s\n' '--print=PRESENT' >> "$out" ;;
      *)         printf '%s\n' "$a" >> "$out" ;;
    esac
  done
}

if [ "$is_verify" -eq 1 ]; then
  [ -n "${MOCK_AGY_VERIFY_ARGS:-}" ] && record_args "$MOCK_AGY_VERIFY_ARGS" "$@"
  printf 'TASK 1: DONE\n'
  exit 0
fi

[ -n "${MOCK_AGY_IMPL_ARGS:-}" ] && record_args "$MOCK_AGY_IMPL_ARGS" "$@"

case "$mode" in
  fail)
    printf 'erro simulado do agy\n'
    exit 1
    ;;
  quota_ok)
    printf 'LOOP-TASK 1 START\n'
    printf 'implementado apesar de quota exceeded no log\n' > quota-ok.txt
    printf 'quota exceeded\n'
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  normal)
    printf 'LOOP-TASK 1 START\n'
    printf 'implementado pelo mock agy\n' > agy-feature.txt
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  *)
    printf 'modo desconhecido no mock: %s\n' "$mode" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$BIN/agy"

init_repo() {
  local dir="$1" task_text="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "Loop Test"
  cat > "$dir/PHASES.md" <<EOF
# Plano de teste agy

## Phase 1: Criar artefato mock

- [ ] $task_text
EOF
  git -C "$dir" add PHASES.md
  git -C "$dir" commit -qm "plano inicial"
}

# 1. Happy path ponta a ponta (impl + Gate 2 + Gate 3 verify)
REPO="$TMP/repo-happy"
init_repo "$REPO" "Criar o arquivo agy-feature.txt"
IMPL_ARGS="$TMP/impl-args.txt"
VERIFY_ARGS="$TMP/verify-args.txt"
cat > "$TMP/hook.sh" <<HOOK
#!/usr/bin/env bash
if [ "\${1:-}" = "phase_done" ]; then
  cp "$REPO/.loop-enginner/state/live.tsv" "$TMP/live-at-phase-done.tsv"
  printf 'HOOK_ENGINE=%s\nHOOK_PROVIDER=%s\n' "\${LOOP_ENGINNER_ENGINE:-}" "\${LOOP_ENGINNER_PROVIDER:-}" > "$TMP/hook-env.txt"
fi
HOOK
chmod +x "$TMP/hook.sh"

(
  cd "$REPO"
  MOCK_AGY_IMPL_ARGS="$IMPL_ARGS" \
  MOCK_AGY_VERIFY_ARGS="$VERIFY_ARGS" \
  LOOP_ENGINNER_HOOK="$TMP/hook.sh" \
  LOOP_ENGINNER_AGY_MODEL="gemini-test" \
  LOOP_ENGINNER_AGY_EFFORT="high" \
  LOOP_ENGINNER_AGY_PRINT_TIMEOUT="45m" \
  LOOP_ENGINNER_VERIFY_MODEL="gemini-fast" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine agy --test-cmd "test -f agy-feature.txt" PHASES.md \
    > "$TMP/happy.log" 2>&1
) || { cat "$TMP/happy.log"; fail "run --engine agy falhou no happy path"; }

[ -f "$REPO/agy-feature.txt" ] || fail "agy-feature.txt nao foi criado"
subject="$(git -C "$REPO" log -1 --pretty=%s)"
case "$subject" in
  "feat(phase-1):"*) ;;
  *) fail "commit inesperado: $subject" ;;
esac

for expected in --print-timeout 45m --output-format text --dangerously-skip-permissions --model gemini-test --effort high --print=PRESENT; do
  grep -qxF -- "$expected" "$IMPL_ARGS" || fail "impl sem arg esperado: $expected"
done
for expected in --print-timeout 45m --output-format text --mode plan --sandbox --model gemini-fast --effort high --print=PRESENT; do
  grep -qxF -- "$expected" "$VERIFY_ARGS" || fail "verify sem arg esperado: $expected"
done
if grep -qxF -- "--dangerously-skip-permissions" "$VERIFY_ARGS"; then
  fail "verify recebeu --dangerously-skip-permissions"
fi

grep -q $'META\tstatus\tfinished' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem status=finished"
grep -q $'META\tengine\tagy' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem engine=agy"
grep -q $'META\tprovider\tagy' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem provider=agy"
grep -q $'META\tmodel\tgemini-test' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem model=gemini-test"
grep -q $'META\treasoning_effort\thigh' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem reasoning_effort=high"
grep -q $'TASK\t1\t1\tdone' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem TASK 1 1 done"
grep -q $'LIVE\t1\tdone' "$TMP/live-at-phase-done.tsv" || fail "live.tsv nao registrou LIVE 1 done durante a fase"
grep -qxF 'HOOK_ENGINE=agy' "$TMP/hook-env.txt" || fail "hook nao recebeu LOOP_ENGINNER_ENGINE=agy"
grep -qxF 'HOOK_PROVIDER=agy' "$TMP/hook-env.txt" || fail "hook nao recebeu LOOP_ENGINNER_PROVIDER=agy"

watch_out="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=50 \
  bash "$ROOT/lib/loop-watch.sh" --once --no-color "$REPO" 2>/dev/null)" \
  || fail "loop-watch --once falhou para agy"
case "$watch_out" in
  *'Engine: agy'*) ;;
  *) fail "painel sem 'Engine: agy'" ;;
esac
case "$watch_out" in
  *'Provider: agy'*) ;;
  *) fail "painel sem 'Provider: agy'" ;;
esac
printf 'ok: happy path impl + gate 2 + gate 3 + painel com engine/provider agy\n'

# 2. doctor e status enxergam agy isoladamente (sem codex nem claude no PATH)
BIN_ONLY_AGY="$TMP/bin-only-agy"
mkdir -p "$BIN_ONLY_AGY"
ln -s "$BIN/agy" "$BIN_ONLY_AGY/agy"
for util in bash git dirname readlink tr awk grep cut head; do
  util_path="$(command -v "$util")" || fail "utilitario ausente para teste isolado: $util"
  ln -s "$util_path" "$BIN_ONLY_AGY/$util"
done

doctor_out="$(PATH="$BIN_ONLY_AGY" bash "$CLI" doctor 2>&1)" \
  || { printf '%s\n' "$doctor_out"; fail "doctor falhou tendo apenas agy no PATH"; }
case "$doctor_out" in
  *'adapters/agy.sh presente'*) ;;
  *) fail "doctor nao validou adapters/agy.sh: $doctor_out" ;;
esac
case "$doctor_out" in
  *'engines no PATH:'*agy*) ;;
  *) fail "doctor nao listou agy no PATH: $doctor_out" ;;
esac

status_out="$(PATH="$BIN_ONLY_AGY" bash "$CLI" status --target "$REPO" 2>&1)" \
  || { printf '%s\n' "$status_out"; fail "status falhou tendo apenas agy no PATH"; }
case "$status_out" in
  *"agy=$BIN_ONLY_AGY/agy"*) ;;
  *) fail "status nao exibiu caminho de agy: $status_out" ;;
esac
case "$status_out" in
  *'provider=agy'*) ;;
  *) fail "status nao exibiu provider=agy do ultimo run: $status_out" ;;
esac
printf 'ok: doctor e status enxergam agy isoladamente\n'

# 3. Metadados de timeout por provider (batch)
(
  # shellcheck source=/dev/null
  source "$ROOT/adapters/agy.sh"
  [ "$(adapter_agy_meta output_mode)" = "batch" ] || fail "output_mode esperado batch"
  [ "$(adapter_agy_meta inactivity_timeout)" = "1800" ] || fail "inactivity_timeout default esperado 1800"
  [ "$(LOOP_ENGINNER_AGY_PRINT_TIMEOUT=45m adapter_agy_meta inactivity_timeout)" = "2700" ] \
    || fail "inactivity_timeout nao herdou PRINT_TIMEOUT=45m"
  [ "$(LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT=120s adapter_agy_meta inactivity_timeout)" = "120" ] \
    || fail "inactivity_timeout explicito nao aplicou 120s"
)
printf 'ok: metadados de timeout por provider (batch)\n'

# 4. Unhappy paths e guarda de exit code
REPO_FAIL="$TMP/repo-fail"
init_repo "$REPO_FAIL" "Falhar no preflight e no gate 0"

if (
  cd "$REPO_FAIL"
  LOOP_ENGINNER_AGY_PRINT_TIMEOUT="invalido" PATH="$BIN:$PATH" \
    bash "$CLI" run --engine agy --no-verify --test-cmd true PHASES.md > /dev/null 2>&1
); then
  fail "preflight aceitou LOOP_ENGINNER_AGY_PRINT_TIMEOUT invalido"
fi

if (
  cd "$REPO_FAIL"
  LOOP_ENGINNER_AGY_EFFORT="invalido" PATH="$BIN:$PATH" \
    bash "$CLI" run --engine agy --no-verify --test-cmd true PHASES.md > /dev/null 2>&1
); then
  fail "preflight aceitou LOOP_ENGINNER_AGY_EFFORT invalido"
fi

if (
  cd "$REPO_FAIL"
  MOCK_AGY_MODE=fail PATH="$BIN:$PATH" \
    bash "$CLI" run --no-supervise --engine agy --max-cycles 1 --no-verify --test-cmd true PHASES.md \
    > "$TMP/fail.log" 2>&1
); then
  fail "run deveria falhar quando agy sai com exit 1"
fi
last_msg="$(git -C "$REPO_FAIL" log -1 --pretty=%s)"
case "$last_msg" in
  "feat(phase-1):"*) fail "criou commit feat apesar da falha no gate 0" ;;
esac

REPO_QUOTA="$TMP/repo-quota"
init_repo "$REPO_QUOTA" "Criar quota-ok.txt ignorando texto de quota quando exit 0"
(
  cd "$REPO_QUOTA"
  MOCK_AGY_MODE=quota_ok \
  LOOP_ENGINNER_LIMIT_WAIT_DEFAULT=60 \
  LOOP_ENGINNER_MAX_LIMIT_WAITS=1 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine agy --no-verify --test-cmd "test -f quota-ok.txt" PHASES.md \
    > "$TMP/quota-ok.log" 2>&1
) || { cat "$TMP/quota-ok.log"; fail "run com exit 0 e texto de quota falhou"; }
if grep -q "Limite de uso atingido" "$TMP/quota-ok.log"; then
  fail "disparou espera por limite mesmo com exit 0"
fi
[ -f "$REPO_QUOTA/quota-ok.txt" ] || fail "quota-ok.txt nao foi criado"
printf 'ok: unhappy paths (timeout/effort invalidos, gate 0 vermelho) e guarda de exit 0\n'
