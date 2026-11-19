#!/usr/bin/env bash
# Adapter do provider OpenCode (opencode) para o Loop Enginner.
# Contrato de sessao: impl (autonomo) e verify (somente-leitura).
# Este arquivo e carregado via `source` por lib/loop.sh.

adapter_opencode_duration_to_seconds() {
  local raw="${1:-}"
  [[ "$raw" =~ ^[0-9]+(s|m|h)?$ ]] || return 1
  case "$raw" in
    *h) printf '%d\n' $(( 10#${raw%h} * 3600 )) ;;
    *m) printf '%d\n' $(( 10#${raw%m} * 60 )) ;;
    *s) printf '%d\n' $(( 10#${raw%s} )) ;;
    *)  printf '%d\n' $(( 10#$raw )) ;;
  esac
}

adapter_opencode_bin() {
  printf '%s' "${LOOP_ENGINNER_OPENCODE_BIN:-opencode}"
}

adapter_opencode_check() {
  local bin inactivity
  bin="$(adapter_opencode_bin)"

  if ! command -v "$bin" >/dev/null 2>&1; then
    printf "OpenCode CLI ('%s') nao encontrado no PATH. Defina LOOP_ENGINNER_OPENCODE_BIN ou instale o opencode.\n" "$bin" >&2
    return 1
  fi

  inactivity="${LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT:-900s}"
  if ! adapter_opencode_duration_to_seconds "$inactivity" >/dev/null; then
    printf "Valor invalido para LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT: '%s'. Use inteiro com sufixo s, m ou h (ex: 900s).\n" "$inactivity" >&2
    return 1
  fi

  return 0
}

adapter_opencode_meta() {
  local field="${1:-}"
  local inactivity
  inactivity="${LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT:-900s}"

  case "$field" in
    provider)           printf 'opencode' ;;
    output_mode)        printf 'batch' ;;
    model)              printf '%s' "${LOOP_ENGINNER_OPENCODE_MODEL:-—}" ;;
    reasoning_effort)   printf '%s' "${LOOP_ENGINNER_OPENCODE_VARIANT:-—}" ;;
    profile)            printf '%s' "${LOOP_ENGINNER_OPENCODE_AGENT:-—}" ;;
    inactivity_timeout) adapter_opencode_duration_to_seconds "$inactivity" | tr -d '\n' || printf '900' ;;
    *)                  printf '—' ;;
  esac
}

adapter_opencode_run() {
  local mode="$1" prompt_file="$2" verify_model="${3:-}"
  local bin eff_model
  bin="$(adapter_opencode_bin)"

  if [ ! -f "$prompt_file" ]; then
    printf "Adapter opencode: arquivo de prompt nao encontrado: %s\n" "$prompt_file" >&2
    return 1
  fi

  local args=(run --format default)

  case "$mode" in
    verify)
      args+=(--agent "${LOOP_ENGINNER_OPENCODE_VERIFY_AGENT:-plan}")
      eff_model="${verify_model:-${LOOP_ENGINNER_OPENCODE_MODEL:-}}"
      if [ -n "$eff_model" ]; then
        args+=(--model "$eff_model")
      fi
      ;;
    impl)
      args+=(--auto)
      if [ -n "${LOOP_ENGINNER_OPENCODE_AGENT:-}" ]; then
        args+=(--agent "$LOOP_ENGINNER_OPENCODE_AGENT")
      fi
      if [ -n "${LOOP_ENGINNER_OPENCODE_MODEL:-}" ]; then
        args+=(--model "$LOOP_ENGINNER_OPENCODE_MODEL")
      fi
      ;;
    *)
      printf "Adapter opencode: modo invalido '%s'. Use 'impl' ou 'verify'.\n" "$mode" >&2
      return 2
      ;;
  esac

  if [ -n "${LOOP_ENGINNER_OPENCODE_VARIANT:-}" ]; then
    args+=(--variant "$LOOP_ENGINNER_OPENCODE_VARIANT")
  fi

  "$bin" "${args[@]}" < "$prompt_file" 2>&1
}

adapter_opencode_gate0() {
  local log_file="$1" rc="$2"
  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine (opencode) saiu com codigo $rc. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi
  return 0
}
