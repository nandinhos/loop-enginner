#!/usr/bin/env bash
#
# hook.example.sh — exemplo de hook de eventos do Loop Enginner.
#
# Para ativar: copie para .loop-enginner/hook.sh e de permissao de execucao
# (chmod +x). O loop chama o hook a cada evento, com timeout de 10s, e nunca
# deixa o hook quebrar o run (falha do hook e ignorada).
#
# Argumentos: $1 = evento, $2 = detalhe.
# Ambiente:  LOOP_ENGINNER_EVENT LOOP_ENGINNER_EVENT_DETAIL
#            LOOP_ENGINNER_ENGINE LOOP_ENGINNER_PHASE_NUM
#            LOOP_ENGINNER_PHASE_TOTAL LOOP_ENGINNER_PHASE_TITLE
#            LOOP_ENGINNER_PHASE_ATTEMPT LOOP_ENGINNER_PHASE_MAX_ATTEMPTS
#            LOOP_ENGINNER_LOG_DIR LOOP_ENGINNER_INPUT_FILE
#
# Eventos: run_start phase_start cycle_start gate_fail phase_done
#          phase_already_done phase_failed limit_wait run_end
set -uo pipefail

event="${1:-${LOOP_ENGINNER_EVENT:-desconhecido}}"
detail="${2:-${LOOP_ENGINNER_EVENT_DETAIL:-}}"

case "$event" in
  phase_done|run_end)
    printf '[loop] %s — %s\n' "$event" "$detail" >> "${LOOP_ENGINNER_LOG_DIR:-.loop-enginner/logs}/hook.log"
    ;;
  phase_failed|gate_fail)
    # Exemplo: troque por curl para o seu webhook, ou remova.
    printf '[loop] ATENCAO %s — %s\n' "$event" "$detail" >> "${LOOP_ENGINNER_LOG_DIR:-.loop-enginner/logs}/hook.log"
    ;;
  *)
    : # eventos informativos: ignore ou registre como preferir
    ;;
esac

exit 0
