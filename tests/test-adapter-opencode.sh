#!/usr/bin/env bash
# Contrato do adapter OpenCode (opencode) com mock no PATH (nunca chama opencode real).
# Prova: impl (--auto) + verify read-only (--agent plan), stdin prompt, timeout batch,
# doctor/status, gate 0 e guarda de exit code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/opencode" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "run" ]; then
  printf 'esperava subcomando run, recebeu: %s\n' "${1:-}" >&2
  exit 2
fi

prompt_stdin="$(cat)"
if [ -z "$prompt_stdin" ]; then
  printf 'stdin de prompt veio vazio\n' >&2
  exit 2
fi

mode="${MOCK_OPENCODE_MODE:-normal}"
is_verify=0
prev=""
for arg in "$@"; do
  if [ "$prev" = "--agent" ] && [ "$arg" = "plan" ]; then
    is_verify=1
    break
  fi
  prev="$arg"
done

record_args() {
  local out="$1"
  shift
  printf '%s\n' "$@" > "$out"
}

if [ "$is_verify" -eq 1 ]; then
  [ -n "${MOCK_OPENCODE_VERIFY_ARGS:-}" ] && record_args "$MOCK_OPENCODE_VERIFY_ARGS" "$@"
  printf 'TASK 1: DONE\n'
  exit 0
fi

[ -n "${MOCK_OPENCODE_IMPL_ARGS:-}" ] && record_args "$MOCK_OPENCODE_IMPL_ARGS" "$@"

case "$mode" in
  fail)
    printf 'erro simulado do opencode\n'
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
    printf 'implementado pelo mock opencode\n' > opencode-feature.txt
    printf 'LOOP-TASK 1 DONE\n'
    exit 0
    ;;
  *)
    printf 'modo desconhecido no mock: %s\n' "$mode" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$BIN/opencode"

init_repo() {
  local dir="$1" task_text="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "Loop Test"
  cat > "$dir/PHASES.md" <<EOF
# Plano de teste opencode

## Phase 1: Criar artefato opencode

- [ ] $task_text
EOF
  git -C "$dir" add PHASES.md
  git -C "$dir" commit -qm "plano inicial"
}

# 1. Happy path ponta a ponta (impl + Gate 2 + Gate 3 verify + hook + painel)
REPO="$TMP/repo-happy"
init_repo "$REPO" "Criar o arquivo opencode-feature.txt"
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
  MOCK_OPENCODE_IMPL_ARGS="$IMPL_ARGS" \
  MOCK_OPENCODE_VERIFY_ARGS="$VERIFY_ARGS" \
  LOOP_ENGINNER_HOOK="$TMP/hook.sh" \
  LOOP_ENGINNER_OPENCODE_MODEL="provider/main-model" \
  LOOP_ENGINNER_OPENCODE_VARIANT="high" \
  LOOP_ENGINNER_VERIFY_MODEL="provider/fast-verify" \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine opencode --test-cmd "test -f opencode-feature.txt" PHASES.md \
    > "$TMP/happy.log" 2>&1
) || { cat "$TMP/happy.log"; fail "run --engine opencode falhou no happy path"; }

[ -f "$REPO/opencode-feature.txt" ] || fail "opencode-feature.txt nao foi criado"
subject="$(git -C "$REPO" log -1 --pretty=%s)"
case "$subject" in
  "feat(phase-1):"*) ;;
  *) fail "commit inesperado: $subject" ;;
esac

for expected in run --format default --auto --model provider/main-model --variant high; do
  grep -qxF -- "$expected" "$IMPL_ARGS" || fail "impl sem arg esperado: $expected"
done
for expected in run --format default --agent plan --model provider/fast-verify --variant high; do
  grep -qxF -- "$expected" "$VERIFY_ARGS" || fail "verify sem arg esperado: $expected"
done
if grep -qxF -- "--auto" "$VERIFY_ARGS"; then
  fail "verify recebeu --auto"
fi

grep -q $'META\tstatus\tfinished' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem status=finished"
grep -q $'META\tengine\topencode' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem engine=opencode"
grep -q $'META\tprovider\topencode' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem provider=opencode"
grep -q $'META\tmodel\tprovider/main-model' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem model=provider/main-model"
grep -q $'META\treasoning_effort\thigh' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem reasoning_effort=high"
grep -q $'TASK\t1\t1\tdone' "$REPO/.loop-enginner/state/run.tsv" || fail "run.tsv sem TASK 1 1 done"
grep -q $'LIVE\t1\tdone' "$TMP/live-at-phase-done.tsv" || fail "live.tsv nao registrou LIVE 1 done durante a fase"
grep -qxF 'HOOK_ENGINE=opencode' "$TMP/hook-env.txt" || fail "hook nao recebeu LOOP_ENGINNER_ENGINE=opencode"
grep -qxF 'HOOK_PROVIDER=opencode' "$TMP/hook-env.txt" || fail "hook nao recebeu LOOP_ENGINNER_PROVIDER=opencode"

watch_out="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=50 \
  bash "$ROOT/lib/loop-watch.sh" --once --no-color "$REPO" 2>/dev/null)" \
  || fail "loop-watch --once falhou para opencode"
case "$watch_out" in
  *'Engine: opencode'*) ;;
  *) fail "painel sem 'Engine: opencode'" ;;
esac
case "$watch_out" in
  *'Provider: opencode'*) ;;
  *) fail "painel sem 'Provider: opencode'" ;;
esac
printf 'ok: happy path impl + gate 2 + gate 3 + hook + painel com opencode\n'

# 2. doctor e status enxergam opencode isoladamente (sem codex, claude ou agy no PATH)
BIN_ONLY_OPENCODE="$TMP/bin-only-opencode"
mkdir -p "$BIN_ONLY_OPENCODE"
ln -s "$BIN/opencode" "$BIN_ONLY_OPENCODE/opencode"
for util in bash git dirname readlink tr awk grep cut head; do
  util_path="$(command -v "$util")" || fail "utilitario ausente para teste isolado: $util"
  ln -s "$util_path" "$BIN_ONLY_OPENCODE/$util"
done

doctor_out="$(PATH="$BIN_ONLY_OPENCODE" bash "$CLI" doctor 2>&1)" \
  || { printf '%s\n' "$doctor_out"; fail "doctor falhou tendo apenas opencode no PATH"; }
case "$doctor_out" in
  *'adapters/opencode.sh presente'*) ;;
  *) fail "doctor nao validou adapters/opencode.sh: $doctor_out" ;;
esac
case "$doctor_out" in
  *'engines no PATH:'*opencode*) ;;
  *) fail "doctor nao listou opencode no PATH: $doctor_out" ;;
esac

status_out="$(PATH="$BIN_ONLY_OPENCODE" bash "$CLI" status --target "$REPO" 2>&1)" \
  || { printf '%s\n' "$status_out"; fail "status falhou tendo apenas opencode no PATH"; }
case "$status_out" in
  *"opencode=$BIN_ONLY_OPENCODE/opencode"*) ;;
  *) fail "status nao exibiu caminho de opencode: $status_out" ;;
esac
case "$status_out" in
  *'provider=opencode'*) ;;
  *) fail "status nao exibiu provider=opencode do ultimo run: $status_out" ;;
esac
printf 'ok: doctor e status enxergam opencode isoladamente\n'

# 3. Metadados de timeout por provider (batch)
(
  # shellcheck source=/dev/null
  source "$ROOT/adapters/opencode.sh"
  [ "$(adapter_opencode_meta output_mode)" = "batch" ] || fail "output_mode esperado batch"
  [ "$(adapter_opencode_meta inactivity_timeout)" = "900" ] || fail "inactivity_timeout default esperado 900"
  [ "$(LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT=20m adapter_opencode_meta inactivity_timeout)" = "1200" ] \
    || fail "inactivity_timeout=20m nao retornou 1200"
  [ "$(LOOP_ENGINNER_OPENCODE_AGENT=custom adapter_opencode_meta profile)" = "custom" ] \
    || fail "profile nao refletiu LOOP_ENGINNER_OPENCODE_AGENT"
)
printf 'ok: metadados de timeout por provider (batch)\n'

# 4. Unhappy paths e guarda de exit code
REPO_FAIL="$TMP/repo-fail"
init_repo "$REPO_FAIL" "Falhar no preflight e no gate 0"

if (
  cd "$REPO_FAIL"
  LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT="invalido" PATH="$BIN:$PATH" \
    bash "$CLI" run --engine opencode --no-verify --test-cmd true PHASES.md > /dev/null 2>&1
); then
  fail "preflight aceitou LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT invalido"
fi

if (
  cd "$REPO_FAIL"
  MOCK_OPENCODE_MODE=fail PATH="$BIN:$PATH" \
    bash "$CLI" run --engine opencode --max-cycles 1 --no-verify --test-cmd true PHASES.md \
    > "$TMP/fail.log" 2>&1
); then
  fail "run deveria falhar quando opencode sai com exit 1"
fi
last_msg="$(git -C "$REPO_FAIL" log -1 --pretty=%s)"
case "$last_msg" in
  "feat(phase-1):"*) fail "criou commit feat apesar da falha no gate 0" ;;
esac

REPO_QUOTA="$TMP/repo-quota"
init_repo "$REPO_QUOTA" "Criar quota-ok.txt ignorando texto de quota quando exit 0"
(
  cd "$REPO_QUOTA"
  MOCK_OPENCODE_MODE=quota_ok \
  LOOP_ENGINNER_LIMIT_WAIT_DEFAULT=60 \
  LOOP_ENGINNER_MAX_LIMIT_WAITS=1 \
  PATH="$BIN:$PATH" \
    bash "$CLI" run --engine opencode --no-verify --test-cmd "test -f quota-ok.txt" PHASES.md \
    > "$TMP/quota-ok.log" 2>&1
) || { cat "$TMP/quota-ok.log"; fail "run com exit 0 e texto de quota falhou"; }
if grep -q "Limite de uso atingido" "$TMP/quota-ok.log"; then
  fail "disparou espera por limite mesmo com exit 0"
fi
[ -f "$REPO_QUOTA/quota-ok.txt" ] || fail "quota-ok.txt nao foi criado"
printf 'ok: unhappy paths (timeout invalido, gate 0 vermelho) e guarda de exit 0\n'
