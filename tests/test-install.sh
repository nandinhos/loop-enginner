#!/usr/bin/env bash
# Install/uninstall reversivel num repo descartavel:
# nada rastreado muda, uninstall remove so o nosso, arquivos do usuario ficam.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert() { "$@" >/dev/null 2>&1 || fail "assert falhou: $*"; }
assert_not() { ! "$@" >/dev/null 2>&1 || fail "assert_not falhou: $*"; }
clean() { [ -z "$(git -C "$REPO" status --porcelain)" ]; }

mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Loop Test"
printf 'base\n' > "$REPO/base.txt"
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm "base"
assert clean

# uninstall sem install: fail-closed
assert_not bash "$CLI" uninstall --target "$REPO"

# install: manifest + exemplos + exclude; arvore continua limpa
bash "$CLI" install --target "$REPO" >/dev/null
assert test -f "$REPO/.loop-enginner/install.manifest"
assert test -f "$REPO/.loop-enginner/config.env.example"
assert test -f "$REPO/.loop-enginner/PHASES.example.md"
assert test -f "$REPO/.loop-enginner/hook.example.sh"
assert grep -qxF '/.loop-enginner/' "$REPO/.git/info/exclude"
assert clean
printf 'ok: install nao suja a arvore\n'

# install de novo: idempotente
bash "$CLI" install --target "$REPO" >/dev/null
assert clean
printf 'ok: install idempotente\n'

# new: cria PHASES.md; segunda vez recusa sobrescrever
bash "$CLI" new --target "$REPO" >/dev/null
assert test -f "$REPO/.loop-enginner/PHASES.md"
assert_not bash "$CLI" new --target "$REPO"
printf 'ok: new cria sem sobrescrever\n'

# arquivos do usuario + runtime simulado
printf '# meu hook\n' > "$REPO/.loop-enginner/hook.sh"
mkdir -p "$REPO/.loop-enginner/state" "$REPO/.loop-enginner/logs" \
         "$REPO/.loop-enginner/prompts" "$REPO/.loop-enginner/run"
printf 'x\n' > "$REPO/.loop-enginner/state/run.tsv"

# uninstall: some o nosso e o runtime; ficam PHASES.md e hook.sh do usuario
bash "$CLI" uninstall --target "$REPO" >/dev/null
assert_not test -e "$REPO/.loop-enginner/install.manifest"
assert_not test -e "$REPO/.loop-enginner/config.env.example"
assert_not test -e "$REPO/.loop-enginner/PHASES.example.md"
assert_not test -e "$REPO/.loop-enginner/hook.example.sh"
assert_not test -e "$REPO/.loop-enginner/state"
assert_not test -e "$REPO/.loop-enginner/logs"
assert test -f "$REPO/.loop-enginner/PHASES.md"
assert test -f "$REPO/.loop-enginner/hook.sh"
assert_not grep -qxF '/.loop-enginner/' "$REPO/.git/info/exclude"
printf 'ok: uninstall remove o nosso e preserva o do usuario\n'

# uninstall de novo: fail-closed; --purge apaga o resto
assert_not bash "$CLI" uninstall --target "$REPO"
bash "$CLI" uninstall --target "$REPO" --purge >/dev/null
assert_not test -e "$REPO/.loop-enginner"
assert clean
printf 'ok: --purge remove tudo e a arvore volta ao estado original\n'
