#!/usr/bin/env bash
# Contrato do rodape dividido (LOGS RECENTES | GATES) em lib/loop-watch.sh.
# Valida W=120, W=100, W=96 e modo estreito W=80 sem estouro de largura/altura.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$ROOT/lib/loop-watch.sh"
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

assert_max_width() {
  local out="$1" max_w="$2" label="$3"
  local line len=0 n=0 in_footer=0
  # Valida todas as linhas das caixas do rodape (LOGS RECENTES e GATES)
  # contra a largura W do terminal.
  while IFS= read -r line; do
    case "$line" in
      ┌*'LOGS RECENTES'*|┌*'GATES'*) in_footer=1 ;;
    esac
    [ "$in_footer" -eq 1 ] || continue
    case "$line" in
      ┌*|│*|└*) ;;
      *) continue ;;
    esac
    n=$((n + 1))
    len=${#line}
    if [ "$len" -gt "$max_w" ]; then
      printf 'Linha %d excedeu W=%d (len=%d) em %s:\n%s\n' "$n" "$max_w" "$len" "$label" "$line" >&2
      exit 1
    fi
  done <<< "$out"
  [ "$n" -gt 0 ] || fail "nenhuma linha do rodape encontrada em $label"
}

REPO="$TMP/repo"
mkdir -p "$REPO/.loop-enginner/state" "$REPO/.loop-enginner/logs"
git -C "$REPO" init -q

# Cenario 1: Fase 1 em curso no Gate 2 com log real -> W=120 e W=96
cat > "$REPO/.loop-enginner/state/run.tsv" <<'EOF'
META	project	demo
META	engine	agy
META	provider	agy
META	model	gemini-3-flash
META	reasoning_effort	high
META	profile	—
META	status	running
META	started	1700000000
META	pid	999999
META	run	run-01
META	cycle_max	3
META	test_cmd	bash test.sh
META	phase_cur	1
META	cycle	1
META	gate	G2
META	activity	rodando suite de testes
META	last_error	
PHASE	1	running	1	pass pass run pending	Adicionar subtracao
TASK	1	1	done	Implementar sub
TASK	1	2	running	Adicionar testes
EOF

cat > "$REPO/.loop-enginner/logs/phase-01.cycle-1.log" <<'EOF'
[00:01:00] Iniciando execucao da fase 1
LOOP-TASK 1 START
LOOP-TASK 1 DONE
PASS calc_sub
EOF

out_120="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=40 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once W=120 falhou"

assert_contains "$out_120" "LOGS RECENTES" "titulo LOGS RECENTES ausente"
assert_contains "$out_120" "GATES (FASE 1)" "titulo GATES (FASE 1) ausente"
assert_contains "$out_120" "G0 Engine" "G0 Engine ausente"
assert_contains "$out_120" "G1 Escrita" "G1 Escrita ausente"
assert_contains "$out_120" "G2 Testes" "G2 Testes ausente"
assert_contains "$out_120" "G3 Verificador" "G3 Verificador ausente"
assert_contains "$out_120" "Sessão concluiu sem erro" "detalhe de G0 pass ausente"
assert_contains "$out_120" "Alterações detectadas no repo" "detalhe de G1 pass ausente"
assert_contains "$out_120" "Rodando testes (bash test.sh)" "detalhe de G2 run ausente"
assert_contains "$out_120" "Revisão read-only task a task" "detalhe de G3 pending ausente"
assert_contains "$out_120" "PASS calc_sub" "linha do log recente ausente no painel esquerdo"
assert_max_width "$out_120" 120 "W=120"

# Confirma renderizacao lado a lado na mesma linha do rodape
if ! printf '%s\n' "$out_120" | grep -qE 'LOGS RECENTES.*GATES \(FASE 1\)'; then
  printf '%s\n' "$out_120" >&2
  fail "LOGS RECENTES e GATES (FASE 1) nao foram renderizados lado a lado em W=120"
fi
printf 'ok: rodape dividido em W=120 com nomes, status e descricoes dos 4 gates\n'

# Cenario 2: W=96 e W=100 com fail/skip e Ultimo erro
cat > "$REPO/.loop-enginner/state/run.tsv" <<'EOF'
META	project	demo
META	engine	agy
META	provider	opencode
META	model	—
META	reasoning_effort	—
META	profile	—
META	status	failed
META	started	1700000000
META	ended	1700000025
META	pid	999999
META	run	run-02
META	cycle_max	3
META	test_cmd	npm test
META	phase_cur	1
META	cycle	2
META	gate	G2
META	activity	
META	last_error	testes falharam com exit 1
PHASE	1	failed	2	pass skip fail pending	Corrigir modulo
TASK	1	1	incomplete	Corrigir bug
EOF

out_100="$(LOOP_ENGINNER_WATCH_COLS=100 LOOP_ENGINNER_WATCH_LINES=40 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once W=100 falhou"
assert_contains "$out_100" "Sem escrita (valida HEAD)" "detalhe G1 skip ausente"
assert_contains "$out_100" "Suíte de testes falhou" "detalhe G2 fail ausente"
assert_contains "$out_100" "Último erro: testes falharam" "Ultimo erro ausente no visor de gates"
assert_contains "$out_100" "Ciclo: 2/3" "resumo de ciclo ausente"
assert_max_width "$out_100" 100 "W=100"

out_96="$(LOOP_ENGINNER_WATCH_COLS=96 LOOP_ENGINNER_WATCH_LINES=36 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once W=96 falhou"
assert_max_width "$out_96" 96 "W=96"
printf 'ok: estado fail/skip e limites W=96..100 respeitados sem quebra de borda\n'

# Cenario 3: Largura estreita (W=80) degrada empilhado sem quebrar bordas
out_80="$(LOOP_ENGINNER_WATCH_COLS=80 LOOP_ENGINNER_WATCH_LINES=30 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once W=80 falhou"
assert_contains "$out_80" "GATES (FASE 1)" "GATES ausente em modo estreito W=80"
assert_contains "$out_80" "G0 Engine" "G0 ausente em modo estreito W=80"
assert_contains "$out_80" "LOGS RECENTES" "LOGS RECENTES ausente em modo estreito W=80"
assert_max_width "$out_80" 80 "W=80"
printf 'ok: modo estreito W=80 empilha GATES e LOGS sem estourar largura\n'

# Cenario 4: Sem arquivo de log (--once ainda mostra o visor de gates)
rm -f "$REPO/.loop-enginner/logs/"*
out_nolog="$(LOOP_ENGINNER_WATCH_COLS=120 LOOP_ENGINNER_WATCH_LINES=40 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once sem log falhou"
assert_contains "$out_nolog" "aguardando saída da sessão atual" "placeholder de log ausente"
assert_contains "$out_nolog" "GATES (FASE 1)" "GATES sumiu quando arquivo de log nao existia"
printf 'ok: --once sem log preserva rodape dividido e exibe visor de gates\n'

# Cenario 5: Enquadramento vertical W=140, H=41 sem estouro de tela e com barra de progresso nos gates
cat > "$REPO/.loop-enginner/state/run.tsv" <<'EOF'
META	project	loop-enginner-demo
META	engine	agy
META	provider	agy
META	model	gemini-3.8-flash-high
META	reasoning_effort	high
META	profile	—
META	status	running
META	started	1700000000
META	pid	2277673
META	run	run-1119-005954-2277673
META	cycle_max	3
META	test_cmd	bash test.sh
META	phase_cur	1
META	cycle	1
META	gate	G0
META	activity	executando sessao do engine (agy)
META	last_error	
PHASE	1	running	1	run pending pending pending	Adicionar operacao sub (subtracao)
TASK	1	1	running	Implementar o subcomando sub em calc.sh
TASK	1	2	pending	Adicionar teste para sub em test.sh
PHASE	2	pending	0	pending pending pending pending	Adicionar operacao mul (multiplicacao)
EOF

out_140="$(LOOP_ENGINNER_WATCH_COLS=140 LOOP_ENGINNER_WATCH_LINES=41 \
  bash "$WATCH" --once --no-color "$REPO" 2>/dev/null)" || fail "watch --once W=140 H=41 falhou"
assert_contains "$out_140" "Progresso: [" "barra de progresso dos gates ausente"
assert_contains "$out_140" "G0 Engine" "G0 Engine ausente"
assert_contains "$out_140" "└" "borda inferior do painel ausente"
assert_max_width "$out_140" 140 "W=140"

# O painel nao pode gerar indicador de rolagem de tabela quando as 3 tasks cabem
if printf '%s\n' "$out_140" | grep -q 'rolagem manual'; then
  fail "indicador de rolagem manual presente mesmo cabendo todas as tasks na tela"
fi
if printf '%s\n' "$out_140" | grep -q 'acima ·'; then
  fail "tabela sofreu paginacao/corte vertical desnecessario em W=140 H=41"
fi
printf 'ok: enquadramento W=140 H=41 sem corte vertical e com barra de progresso dos gates\n'
