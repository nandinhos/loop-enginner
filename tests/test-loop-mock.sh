#!/usr/bin/env bash
# Run completo com engine mock: 1 fase, 1 task, gate 2 'true', gate 3 off.
# Prova o contrato: sessao escreve -> gates -> 1 commit -> estado publicado.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/loop-enginner"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
BIN="$TMP/bin"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$REPO" "$BIN"

# Engine mock: le o prompt do stdin, "implementa" criando feature.txt.
cat > "$BIN/codex" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
printf 'LOOP-TASK 1 START\n'
printf 'implementado pelo mock\n' > feature.txt
printf 'LOOP-TASK 1 DONE\n'
exit 0
MOCK
chmod +x "$BIN/codex"

git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Loop Test"
cat > "$REPO/PHASES.md" <<'EOF'
# Plano de teste

## Phase 1: Criar feature.txt

- [ ] Criar o arquivo feature.txt com uma linha de texto
EOF
git -C "$REPO" add PHASES.md
git -C "$REPO" commit -qm "plano de teste"

cd "$REPO"
PATH="$BIN:$PATH" bash "$CLI" run --engine codex --no-verify --test-cmd true PHASES.md \
  > "$TMP/run.log" 2>&1 || { cat "$TMP/run.log"; fail "run saiu != 0"; }

[ -f feature.txt ] || fail "feature.txt nao foi criado"
subject="$(git log -1 --pretty=%s)"
case "$subject" in
  "feat(phase-1):"*) ;;
  *) fail "commit inesperado: $subject" ;;
esac
printf 'ok: run gerou 1 commit por fase (%s)\n' "$subject"

[ -f .loop-enginner/state/run.tsv ] || fail "estado nao publicado em .loop-enginner/state/run.tsv"
grep -q $'META\tstatus\tfinished' .loop-enginner/state/run.tsv \
  || fail "run.tsv sem status=finished"
[ -f .loop-enginner/run/phase-01.md ] || fail "fragmento da fase ausente em .loop-enginner/run/"
printf 'ok: estado e runtime dentro de .loop-enginner/\n'

# O painel desenha um frame a partir do estado, com o banner.
out="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=50 \
  bash "$ROOT/lib/loop-watch.sh" --once --no-color "$REPO" 2>/dev/null)" \
  || fail "loop-watch --once falhou"
case "$out" in
  *'██'*) ;;
  *) fail "banner ANSI Shadow ausente no frame do painel" ;;
esac
case "$out" in
  *'EXECUÇÃO'*|*'EXECU'*) ;;
  *) fail "caixa EXECUCAO ausente no frame do painel" ;;
esac
printf 'ok: painel renderiza banner e caixas a partir do estado\n'
