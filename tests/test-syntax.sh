#!/usr/bin/env bash
# Sintaxe de todos os scripts + shellcheck (severidade error) quando houver.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for f in "$ROOT/bin/loop-enginner" "$ROOT/install-global.sh" \
         "$ROOT/lib/loop.sh" "$ROOT/lib/loop-watch.sh" \
         "$ROOT/templates/hook.example.sh" "$ROOT"/tests/*.sh; do
  bash -n "$f" || fail "bash -n: $f"
  [ -x "$f" ] || fail "nao executavel: $f"
done
for f in "$ROOT"/adapters/*.sh "$ROOT/lib/fallback.sh" "$ROOT/lib/recovery.sh"; do
  bash -n "$f" || fail "bash -n: $f"
done
printf 'ok: bash -n e +x em todos os scripts\n'

python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' \
  "$ROOT/tools/fork-from-upstream.py" \
  || fail "sintaxe: tools/fork-from-upstream.py"
printf 'ok: tools/fork-from-upstream.py compila\n'

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$ROOT/bin/loop-enginner" "$ROOT/install-global.sh" \
    "$ROOT/lib/loop.sh" "$ROOT/lib/fallback.sh" "$ROOT/lib/recovery.sh" "$ROOT/lib/loop-watch.sh" "$ROOT"/adapters/*.sh "$ROOT"/tests/*.sh \
    || fail "shellcheck -S error"
  printf 'ok: shellcheck -S error\n'
else
  printf 'skip: shellcheck ausente\n'
fi

# A lib e os adapters nao podem voltar a acoplar nos nomes/projetos de origem.
if grep -nE 'RALPH_|RALPH-TASK|ralph\.sh|ralph-watch|\.phases/|bc-harness|claude-profiles|ralph-provider-bin|ralph-events|watcher-features|ralph-dispatch|ralph-watcher|ralph-codex-dispatch' \
     "$ROOT/lib/loop.sh" "$ROOT/lib/fallback.sh" "$ROOT/lib/recovery.sh" "$ROOT/lib/loop-watch.sh" "$ROOT"/adapters/*.sh; then
  fail "residuo de acoplamento na lib/adapters (ver acima)"
fi
printf 'ok: lib e adapters sem residuos de acoplamento\n'
