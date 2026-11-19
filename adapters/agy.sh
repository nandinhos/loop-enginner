#!/usr/bin/env bash
# Adapter do provider Antigravity (agy) para o Loop Enginner.
# Contrato de sessao: impl (autonomo) e verify (somente-leitura).
# Este arquivo e carregado via `source` por lib/loop.sh.

adapter_agy_duration_to_seconds() {
  local raw="${1:-}"
  [[ "$raw" =~ ^[0-9]+(s|m|h)?$ ]] || return 1
  case "$raw" in
    *h) printf '%d\n' $(( 10#${raw%h} * 3600 )) ;;
    *m) printf '%d\n' $(( 10#${raw%m} * 60 )) ;;
    *s) printf '%d\n' $(( 10#${raw%s} )) ;;
    *)  printf '%d\n' $(( 10#$raw )) ;;
  esac
}

adapter_agy_bin() {
  printf '%s' "${LOOP_ENGINNER_AGY_BIN:-agy}"
}

adapter_agy_models() {
  local bin models=() line
  bin="$(adapter_agy_bin)"
  if command -v "$bin" >/dev/null 2>&1; then
    while IFS= read -r line; do
      [ -n "$line" ] && models+=("$line")
    done < <("$bin" models 2>/dev/null | tr -d '\r' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -v 'Fetching available models' | awk '{print $1}')
  fi
  if [ "${#models[@]}" -eq 0 ]; then
    models=(
      "gemini-3.8-flash-high"
      "gemini-3.8-flash-medium"
      "gemini-3.8-flash-low"
      "claude-sonnet-4-6"
      "claude-opus-4-6-thinking"
      "gpt-oss-120b-medium"
    )
  fi
  printf '%s\n' "${models[@]}"
}

adapter_agy_efforts() {
  printf '%s\n' "low" "medium" "high" "xhigh" "max"
}

adapter_agy_check() {
  local bin timeout inactivity effort
  bin="$(adapter_agy_bin)"

  if ! command -v "$bin" >/dev/null 2>&1; then
    printf "Antigravity CLI ('%s') nao encontrado no PATH. Defina LOOP_ENGINNER_AGY_BIN ou instale o agy.\n" "$bin" >&2
    return 1
  fi

  timeout="${LOOP_ENGINNER_AGY_PRINT_TIMEOUT:-30m}"
  if ! adapter_agy_duration_to_seconds "$timeout" >/dev/null; then
    printf "Valor invalido para LOOP_ENGINNER_AGY_PRINT_TIMEOUT: '%s'. Use inteiro com sufixo s, m ou h (ex: 30m).\n" "$timeout" >&2
    return 1
  fi

  if [ -n "${LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT:-}" ]; then
    inactivity="$LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT"
    if ! adapter_agy_duration_to_seconds "$inactivity" >/dev/null; then
      printf "Valor invalido para LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT: '%s'. Use inteiro com sufixo s, m ou h (ex: 30m).\n" "$inactivity" >&2
      return 1
    fi
  fi

  if [ -n "${LOOP_ENGINNER_AGY_EFFORT:-}" ]; then
    effort="$LOOP_ENGINNER_AGY_EFFORT"
    case "$effort" in
      low|medium|high|xhigh|max) ;;
      *)
        printf "Valor invalido para LOOP_ENGINNER_AGY_EFFORT: '%s'. Use low, medium, high, xhigh ou max.\n" "$effort" >&2
        return 1
        ;;
    esac
  fi

  return 0
}

adapter_agy_meta() {
  local field="${1:-}"
  local timeout inactivity
  timeout="${LOOP_ENGINNER_AGY_PRINT_TIMEOUT:-30m}"
  inactivity="${LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT:-$timeout}"

  case "$field" in
    provider)           printf 'agy' ;;
    output_mode)        printf 'batch' ;;
    model)              printf '%s' "${LOOP_ENGINNER_AGY_MODEL:-—}" ;;
    reasoning_effort)   printf '%s' "${LOOP_ENGINNER_AGY_EFFORT:-—}" ;;
    profile)            printf '—' ;;
    print_timeout)      printf '%s' "$timeout" ;;
    inactivity_timeout) adapter_agy_duration_to_seconds "$inactivity" | tr -d '\n' || printf '1800' ;;
    *)                  printf '—' ;;
  esac
}

adapter_agy_run() {
  local mode="$1" prompt_file="$2" verify_model="${3:-}"
  local bin timeout prompt_text eff_model
  bin="$(adapter_agy_bin)"
  timeout="${LOOP_ENGINNER_AGY_PRINT_TIMEOUT:-30m}"

  if [ ! -f "$prompt_file" ]; then
    printf "Adapter agy: arquivo de prompt nao encontrado: %s\n" "$prompt_file" >&2
    return 1
  fi

  local args=(--print-timeout "$timeout" --output-format text)

  case "$mode" in
    verify)
      args+=(--mode plan --sandbox)
      eff_model="${verify_model:-${LOOP_ENGINNER_AGY_MODEL:-}}"
      if [ -n "$eff_model" ]; then
        args+=(--model "$eff_model")
      fi
      ;;
    impl)
      args+=(--dangerously-skip-permissions)
      if [ -n "${LOOP_ENGINNER_AGY_MODEL:-}" ]; then
        args+=(--model "$LOOP_ENGINNER_AGY_MODEL")
      fi
      ;;
    *)
      printf "Adapter agy: modo invalido '%s'. Use 'impl' ou 'verify'.\n" "$mode" >&2
      return 2
      ;;
  esac

  if [ -n "${LOOP_ENGINNER_AGY_EFFORT:-}" ]; then
    args+=(--effort "$LOOP_ENGINNER_AGY_EFFORT")
  fi

  prompt_text="$(cat "$prompt_file")"
  "$bin" "${args[@]}" --print="$prompt_text" < /dev/null 2>&1
}

adapter_agy_gate0() {
  local log_file="$1" rc="$2"
  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine (agy) saiu com codigo $rc. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  return 0
}
