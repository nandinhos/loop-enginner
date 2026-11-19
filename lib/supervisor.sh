#!/usr/bin/env bash
# supervisor.sh — monitor de continuidade com retomada automatica (ate 3x) e
# deteccao de trava silenciosa para o Loop Enginner.
set -euo pipefail

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$HOME_DIR/lib"

STATE_DIR=".loop-enginner/state"
RUN_STATE="$STATE_DIR/run.tsv"
LIVE_STATE="$STATE_DIR/live.tsv"
RECOVERY_STATE="$STATE_DIR/recovery.tsv"
HISTORY_FILE="$STATE_DIR/history.tsv"
LOG_DIR=".loop-enginner/logs"

MAX_RECOVERIES="${LOOP_ENGINNER_MAX_RECOVERIES:-3}"
SUP_INTERVAL="${LOOP_ENGINNER_SUPERVISOR_INTERVAL:-15}"
SUP_STALL_TIMEOUT="${LOOP_ENGINNER_SUPERVISOR_STALL_TIMEOUT:-1800}"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      exec bash "$LIB_DIR/loop.sh" "$@"
      ;;
  esac
done

if ! [[ "$MAX_RECOVERIES" =~ ^[0-9]+$ ]]; then
  printf 'loop-enginner: erro: LOOP_ENGINNER_MAX_RECOVERIES invalido: %s (use inteiro >= 0)\n' "$MAX_RECOVERIES" >&2
  exit 1
fi
if ! [[ "$SUP_INTERVAL" =~ ^[0-9]+$ ]] || [ "$SUP_INTERVAL" -lt 1 ]; then
  printf 'loop-enginner: erro: LOOP_ENGINNER_SUPERVISOR_INTERVAL invalido: %s (use inteiro >= 1)\n' "$SUP_INTERVAL" >&2
  exit 1
fi
if ! [[ "$SUP_STALL_TIMEOUT" =~ ^[0-9]+$ ]]; then
  printf 'loop-enginner: erro: LOOP_ENGINNER_SUPERVISOR_STALL_TIMEOUT invalido: %s (use inteiro >= 0)\n' "$SUP_STALL_TIMEOUT" >&2
  exit 1
fi

sup_log()  { printf '\033[0;34m[%s]\033[0m [supervisor] %s\n' "$(date '+%H:%M:%S')" "$*"; }
sup_warn() { printf '\033[1;33m[%s]\033[0m [supervisor] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
sup_fail() { printf '\033[0;31m[%s]\033[0m [supervisor] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

sup_meta_from_run() {
  local key="$1"
  [ -f "$RUN_STATE" ] || return 0
  awk -F'\t' -v k="$key" '$1=="META" && $2==k {v=$3} END {print v}' "$RUN_STATE" 2>/dev/null || true
}

sup_write_recovery() {
  local st="$1" used="$2" limit="$3" action="$4"
  mkdir -p "$STATE_DIR"
  local tmp="$RECOVERY_STATE.$$"
  local clean_action
  clean_action="$(printf '%s' "$action" | tr '\t\r\n' '   ')"
  {
    printf 'META\tsupervisor_state\t%s\n' "$st"
    printf 'META\tretries_used\t%s\n' "$used"
    printf 'META\tretries_limit\t%s\n' "$limit"
    printf 'META\tlast_action\t%s\n' "$clean_action"
    printf 'META\tupdated_at\t%s\n' "$(date +%s)"
  } > "$tmp"
  mv -f "$tmp" "$RECOVERY_STATE"
}

sup_history_record() {
  local event="$1" phase="$2" detail="${3:-}"
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$event" "$phase" "$detail" >> "$HISTORY_FILE"
}

sup_emit_hook() {
  local event="$1" detail="${2:-}" hook=""
  if [ -n "${LOOP_ENGINNER_HOOK:-}" ] && [ -x "${LOOP_ENGINNER_HOOK}" ]; then
    hook="$LOOP_ENGINNER_HOOK"
  elif [ -x "./.loop-enginner/hook.sh" ]; then
    hook="$(pwd)/.loop-enginner/hook.sh"
  fi
  [ -n "$hook" ] || return 0
  LOOP_ENGINNER_EVENT="$event" \
  LOOP_ENGINNER_EVENT_DETAIL="$detail" \
    timeout 10 "$hook" "$event" "$detail" >/dev/null 2>&1 || true
}

sup_kill_tree() {
  local pid="$1" sig="${2:-TERM}" child
  while IFS= read -r child; do
    child="${child//[[:space:]]/}"
    [ -n "$child" ] || continue
    sup_kill_tree "$child" "$sig"
  done < <(ps -o pid= --ppid "$pid" 2>/dev/null || true)
  kill "-$sig" "$pid" 2>/dev/null || true
}

sup_mtime() {
  local p="$1"
  [ -e "$p" ] || { printf '0'; return 0; }
  stat -c '%Y' "$p" 2>/dev/null || stat -f '%m' "$p" 2>/dev/null || printf '0'
}

sup_latest_activity_mtime() {
  local best=0 m f
  for f in "$RUN_STATE" "$LIVE_STATE" "$LOG_DIR"/*.log; do
    [ -e "$f" ] || continue
    m="$(sup_mtime "$f")"
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    [ "$m" -gt "$best" ] && best="$m"
  done
  printf '%s' "$best"
}

sup_build_resume_args() {
  local -a next=()
  local has_resume=0 skip_next=0 arg
  for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      --from)   skip_next=1; continue ;;
      --from=*) continue ;;
      --resume) has_resume=1; next+=("$arg") ;;
      *)        next+=("$arg") ;;
    esac
  done
  [ "$has_resume" -eq 1 ] || next+=(--resume)
  RUN_ARGS=("${next[@]}")
}

sup_render_report() {
  if [ -x "$LIB_DIR/report.sh" ]; then
    bash "$LIB_DIR/report.sh" --target "$(pwd)" || true
  fi
}

SUP_STOP=0
CHILD_PID=""

sup_on_signal() {
  SUP_STOP=1
  if [ -n "${CHILD_PID:-}" ]; then
    sup_kill_tree "$CHILD_PID" TERM 2>/dev/null || true
  fi
}

trap sup_on_signal INT TERM

main() {
  local -a RUN_ARGS=("$@")
  local retries_used=0
  local sup_start_epoch sup_start_head
  sup_start_epoch="$(date +%s)"
  sup_start_head="$(git rev-parse HEAD 2>/dev/null || true)"

  export LOOP_ENGINNER_SUPERVISED=1
  export LOOP_ENGINNER_REPORT_SKIP=1
  export LOOP_ENGINNER_RUN_START_EPOCH="$sup_start_epoch"
  export LOOP_ENGINNER_RUN_START_HEAD="$sup_start_head"

  local had_prev_recovery=0 prev_recovery_backup=""
  if [ -f "$RECOVERY_STATE" ]; then
    had_prev_recovery=1
    prev_recovery_backup="$(cat "$RECOVERY_STATE" 2>/dev/null || true)"
  fi

  while true; do
    local run_id_before="" run_id_after="" status_after="" phase_cur=""
    run_id_before="$(sup_meta_from_run run)"

    if [ "$retries_used" -eq 0 ]; then
      sup_write_recovery monitoring "$retries_used" "$MAX_RECOVERIES" "monitorando execucao inicial"
    else
      sup_write_recovery retrying "$retries_used" "$MAX_RECOVERIES" "retomada automatica $retries_used/$MAX_RECOVERIES com debug sistematico"
    fi

    local last_activity_ts next_check_ts stalled=0
    last_activity_ts="$(date +%s)"
    next_check_ts=$((last_activity_ts + SUP_INTERVAL))

    bash "$LIB_DIR/loop.sh" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} &
    CHILD_PID=$!

    while kill -0 "$CHILD_PID" 2>/dev/null; do
      [ "$SUP_STOP" -eq 1 ] && break
      sleep 0.2
      [ "$SUP_STOP" -eq 1 ] && break
      [ "$SUP_STALL_TIMEOUT" -eq 0 ] && continue

      local now
      now="$(date +%s)"
      if [ "$now" -lt "$next_check_ts" ]; then
        continue
      fi
      next_check_ts=$((now + SUP_INTERVAL))

      local st latest
      st="$(sup_meta_from_run status)"
      if [ "$st" = "waiting" ]; then
        last_activity_ts="$now"
        continue
      fi
      latest="$(sup_latest_activity_mtime)"
      [[ "$latest" =~ ^[0-9]+$ ]] && [ "$latest" -gt "$last_activity_ts" ] && last_activity_ts="$latest"

      if [ $((now - last_activity_ts)) -ge "$SUP_STALL_TIMEOUT" ]; then
        stalled=1
        sup_warn "Trava silenciosa detectada (${SUP_STALL_TIMEOUT}s sem atualizacao em logs/estado); encerrando tentativa para retomar."
        sup_write_recovery retrying "$retries_used" "$MAX_RECOVERIES" "trava silenciosa detectada (${SUP_STALL_TIMEOUT}s)"
        sup_kill_tree "$CHILD_PID" TERM
        local w=0
        while [ "$w" -lt 5 ] && kill -0 "$CHILD_PID" 2>/dev/null; do
          sleep 0.2
          w=$((w + 1))
        done
        if kill -0 "$CHILD_PID" 2>/dev/null; then
          sup_kill_tree "$CHILD_PID" KILL
        fi
        break
      fi
    done

    local child_rc=0
    if wait "$CHILD_PID"; then
      child_rc=0
    else
      child_rc=$?
    fi
    CHILD_PID=""

    if [ "$SUP_STOP" -eq 1 ]; then
      sup_warn "Supervisor interrompido por sinal; encerrando sem retomar."
      exit 130
    fi

    run_id_after="$(sup_meta_from_run run)"
    status_after="$(sup_meta_from_run status)"
    phase_cur="$(sup_meta_from_run phase_cur)"

    if [ "$child_rc" -eq 0 ] && [ "$status_after" = "finished" ]; then
      sup_write_recovery finished "$retries_used" "$MAX_RECOVERIES" "execucao concluida com sucesso"
      sup_render_report
      return 0
    fi

    if [ "$child_rc" -eq 0 ] && [ "$status_after" = "paused" ]; then
      sup_write_recovery paused "$retries_used" "$MAX_RECOVERIES" "pausado graciosamente pelo operador"
      sup_render_report
      return 0
    fi

    # Short-circuit de preflight: falha antes de criar/atualizar run.tsv nao consome retries.
    if [ "$stalled" -eq 0 ] && { [ ! -f "$RUN_STATE" ] || [ "$run_id_after" = "$run_id_before" ]; }; then
      if [ "$had_prev_recovery" -eq 1 ] && [ -n "$prev_recovery_backup" ]; then
        printf '%s\n' "$prev_recovery_backup" > "$RECOVERY_STATE"
      elif [ "$had_prev_recovery" -eq 0 ]; then
        rm -f "$RECOVERY_STATE" 2>/dev/null || true
      fi
      exit "$child_rc"
    fi

    if [ "$retries_used" -ge "$MAX_RECOVERIES" ]; then
      sup_write_recovery recovery_required "$retries_used" "$MAX_RECOVERIES" "limite de $MAX_RECOVERIES retomadas atingido"
      sup_fail "Supervisor esgotou o limite de $MAX_RECOVERIES retomadas automaticas (estado: recovery_required)."
      sup_emit_hook supervisor_exhausted "limite de $MAX_RECOVERIES retomadas esgotado na fase ${phase_cur:-?}"
      sup_render_report
      sup_fail "Consulte o relatorio em .loop-enginner/state/report.md e os patches em .loop-enginner/state/recovery/"
      return 1
    fi

    retries_used=$((retries_used + 1))
    local reason="falha na fase ${phase_cur:-?}"
    [ "$stalled" -eq 1 ] && reason="trava silenciosa (${SUP_STALL_TIMEOUT}s) na fase ${phase_cur:-?}"
    sup_warn "Acionando retomada automatica $retries_used/$MAX_RECOVERIES ($reason)..."
    sup_history_record supervisor_retry "${phase_cur:-0}" "retomada $retries_used/$MAX_RECOVERIES ($reason)"
    sup_emit_hook supervisor_retry "retomada $retries_used/$MAX_RECOVERIES ($reason)"
    sup_build_resume_args ${RUN_ARGS[@]+"${RUN_ARGS[@]}"}
  done
}

main "$@"
