#!/usr/bin/env bash
# Cadeia de fallback configuravel, decisao pos-falha e vigia de progresso por provider.
# Carregado via `source` por lib/loop.sh.

FALLBACK_KNOWN_ORDER=(codex claude agy opencode)
FALLBACK_DEFAULT_PATTERN='rate limit reached|quota exceeded|usage limit|hit your (session|usage|[0-9]+-hour) limit|[0-9]+-hour limit reached|insufficient[_ -]quota|too many requests|authentication failed|unauthorized|invalid (api )?key|service unavailable|upgrade to pro|purchase more credits|failed to refresh available models|turn\.failed'
FALLBACK_NOISE_PATTERN='retrying .*(stream|model)|^[[:space:]]*$'

fallback_duration_to_seconds() {
  local raw="${1:-}"
  [[ "$raw" =~ ^[0-9]+(s|m|h)?$ ]] || return 1
  case "$raw" in
    *h) printf '%d\n' $(( 10#${raw%h} * 3600 )) ;;
    *m) printf '%d\n' $(( 10#${raw%m} * 60 )) ;;
    *s) printf '%d\n' $(( 10#${raw%s} )) ;;
    *)  printf '%d\n' $(( 10#$raw )) ;;
  esac
}

fallback_provider_exists() {
  local name="${1:-}"
  case "$name" in
    codex|claude) return 0 ;;
    *) is_adapter_engine "$name" ;;
  esac
}

fallback_provider_check() {
  local name="${1:-}"
  if is_adapter_engine "$name"; then
    load_adapter "$name" || { printf "Falha ao carregar adapter: %s\n" "$name" >&2; return 1; }
    "adapter_${name}_check"
    return $?
  fi
  case "$name" in
    codex)
      if ! command -v codex >/dev/null 2>&1; then
        printf "codex CLI nao encontrado. Instale com: npm install -g @openai/codex\n" >&2
        return 1
      fi
      return 0
      ;;
    claude)
      if ! command -v claude >/dev/null 2>&1; then
        printf "Claude Code CLI nao encontrado. Instale com: npm install -g @anthropic-ai/claude-code\n" >&2
        return 1
      fi
      return 0
      ;;
    *)
      printf "Provider invalido na cadeia de fallback: '%s'. Use codex, claude, agy ou opencode.\n" "$name" >&2
      return 1
      ;;
  esac
}

fallback_provider_inactivity_timeout() {
  local provider="${1:-}"
  if is_adapter_engine "$provider" && declare -F "adapter_${provider}_meta" >/dev/null 2>&1; then
    "adapter_${provider}_meta" inactivity_timeout
    return 0
  fi
  local raw
  case "$provider" in
    codex)  raw="${LOOP_ENGINNER_CODEX_INACTIVITY_TIMEOUT:-${LOOP_ENGINNER_PROVIDER_INACTIVITY_TIMEOUT:-300}}" ;;
    claude) raw="${LOOP_ENGINNER_CLAUDE_INACTIVITY_TIMEOUT:-${LOOP_ENGINNER_PROVIDER_INACTIVITY_TIMEOUT:-300}}" ;;
    *)      raw="${LOOP_ENGINNER_PROVIDER_INACTIVITY_TIMEOUT:-300}" ;;
  esac
  fallback_duration_to_seconds "$raw" || printf '300\n'
}

fallback_provider_meta() {
  local provider="${1:-}" field="${2:-}"
  if is_adapter_engine "$provider" && declare -F "adapter_${provider}_meta" >/dev/null 2>&1; then
    "adapter_${provider}_meta" "$field"
    return 0
  fi
  case "$field" in
    provider)           printf '%s' "$provider" ;;
    output_mode)        printf 'streaming' ;;
    model)
      if [ "$provider" = "codex" ]; then
        printf '%s' "${LOOP_ENGINNER_CODEX_MODEL:-—}"
      else
        printf '%s' "${CLAUDE_MODEL:-—}"
      fi
      ;;
    profile)
      if [ "$provider" = "codex" ]; then
        printf '%s' "${LOOP_ENGINNER_CODEX_PROFILE:-—}"
      else
        printf '—'
      fi
      ;;
    reasoning_effort)
      if [ "$provider" = "codex" ]; then
        printf '%s' "${LOOP_ENGINNER_CODEX_REASONING_EFFORT:-—}"
      else
        printf '—'
      fi
      ;;
    inactivity_timeout) fallback_provider_inactivity_timeout "$provider" | tr -d '\n' ;;
    *)                  printf '—' ;;
  esac
}

fallback_watchdog_active_for() {
  local provider="${1:-}" limit
  limit="$(fallback_provider_inactivity_timeout "$provider")"
  [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -gt 0 ] || return 1

  if [ "${#FALLBACK_PROVIDERS[@]}" -gt 1 ]; then
    return 0
  fi
  if [ -n "${LOOP_ENGINNER_PROVIDER_INACTIVITY_TIMEOUT:-}" ]; then
    return 0
  fi
  case "$provider" in
    codex)    [ -n "${LOOP_ENGINNER_CODEX_INACTIVITY_TIMEOUT:-}" ] && return 0 ;;
    claude)   [ -n "${LOOP_ENGINNER_CLAUDE_INACTIVITY_TIMEOUT:-}" ] && return 0 ;;
    agy)      [ -n "${LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT:-}" ] && return 0 ;;
    opencode) [ -n "${LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT:-}" ] && return 0 ;;
  esac
  return 1
}

fallback_validate_timeouts() {
  local name val
  for name in \
    LOOP_ENGINNER_PROVIDER_INACTIVITY_TIMEOUT \
    LOOP_ENGINNER_CODEX_INACTIVITY_TIMEOUT \
    LOOP_ENGINNER_CLAUDE_INACTIVITY_TIMEOUT; do
    val="${!name:-}"
    if [ -n "$val" ] && ! fallback_duration_to_seconds "$val" >/dev/null; then
      printf "Valor invalido para %s: '%s'. Use inteiro com sufixo s, m ou h (ex: 300s).\n" "$name" "$val" >&2
      return 1
    fi
  done
  if [ -n "${LOOP_ENGINNER_WATCHDOG_POLL:-}" ]; then
    if ! [[ "$LOOP_ENGINNER_WATCHDOG_POLL" =~ ^[0-9]+$ ]] || [ "$LOOP_ENGINNER_WATCHDOG_POLL" -lt 1 ]; then
      printf "Valor invalido para LOOP_ENGINNER_WATCHDOG_POLL: '%s'. Use inteiro >= 1.\n" "$LOOP_ENGINNER_WATCHDOG_POLL" >&2
      return 1
    fi
  fi
  return 0
}

fallback_resolve_chain() {
  local primary="$1" spec="${2:-}"
  FALLBACK_PROVIDERS=("$primary")
  FALLBACK_INDEX=0
  ACTIVE_PROVIDER="$primary"

  [ -n "$spec" ] || return 0

  if [ "$spec" = "auto" ]; then
    local p
    for p in "${FALLBACK_KNOWN_ORDER[@]}"; do
      [ "$p" = "$primary" ] && continue
      if fallback_provider_exists "$p" && fallback_provider_check "$p" >/dev/null 2>&1; then
        FALLBACK_PROVIDERS+=("$p")
      fi
    done
    return 0
  fi

  local norm="${spec//,/ }"
  local -a tokens=()
  local tok seen existing
  read -ra tokens <<< "$norm"
  for tok in "${tokens[@]}"; do
    [ -n "$tok" ] || continue
    if ! fallback_provider_exists "$tok"; then
      printf "Provider desconhecido em LOOP_ENGINNER_FALLBACK_CHAIN: '%s'. Use codex, claude, agy ou opencode.\n" "$tok" >&2
      return 1
    fi
    fallback_provider_check "$tok" || return 1
    seen=0
    for existing in "${FALLBACK_PROVIDERS[@]}"; do
      if [ "$existing" = "$tok" ]; then
        seen=1
        break
      fi
    done
    [ "$seen" -eq 0 ] && FALLBACK_PROVIDERS+=("$tok")
  done

  return 0
}

fallback_should_escalate() {
  local provider="$1" rc="$2" log_file="$3" stalled="${4:-0}"
  if [ "$stalled" -eq 1 ]; then
    printf 'travamento-sem-progresso'
    return 0
  fi

  local pattern="${LOOP_ENGINNER_FALLBACK_PATTERN:-$FALLBACK_DEFAULT_PATTERN}"

  if [ "$provider" = "claude" ]; then
    local result_line="" failed=0
    result_line="$(grep -F '"type":"result"' "$log_file" 2>/dev/null | tail -n 1 || true)"
    [ -z "$result_line" ] && result_line="$(grep -F '"type": "result"' "$log_file" 2>/dev/null | tail -n 1 || true)"
    if [ "$rc" -ne 0 ]; then
      failed=1
    elif [ -n "$result_line" ] && grep -qE '"is_error"[[:space:]]*:[[:space:]]*true' <<< "$result_line"; then
      failed=1
    fi
    [ "$failed" -eq 1 ] || return 1

    local claude_pat="${pattern}|\"api_error_status\"[[:space:]]*:[[:space:]]*429"
    if [ -n "$result_line" ] && grep -qiE "$claude_pat" <<< "$result_line"; then
      printf 'indisponivel-ou-limite'
      return 0
    fi
    if tail -n 60 "$log_file" 2>/dev/null | grep -qiE "$claude_pat"; then
      printf 'indisponivel-ou-limite'
      return 0
    fi
    return 1
  fi

  # Guarda absoluta: sessao que terminou com sucesso (rc=0) nunca dispara fallback.
  [ "$rc" -ne 0 ] || return 1

  if tail -n 60 "$log_file" 2>/dev/null | grep -qiE "$pattern"; then
    printf 'indisponivel-ou-limite'
    return 0
  fi
  return 1
}

fallback_kill_tree() {
  local pid="$1" sig="${2:-TERM}" child
  while IFS= read -r child; do
    child="${child//[[:space:]]/}"
    [ -n "$child" ] || continue
    fallback_kill_tree "$child" "$sig"
  done < <(ps -o pid= --ppid "$pid" 2>/dev/null || true)
  kill "-$sig" "$pid" 2>/dev/null || true
}

fallback_watchdog_start() {
  local log_file="$1" stamp="$2" limit_secs="$3" poll="${4:-${LOOP_ENGINNER_WATCHDOG_POLL:-5}}"
  (
    local last_count=0 since cur idle target_pid
    since="$(date +%s)"
    while sleep "$poll"; do
      [ -f "$stamp.done" ] && exit 0
      cur="$(grep -cvE "$FALLBACK_NOISE_PATTERN" "$log_file" 2>/dev/null || true)"
      [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
      if [ "$cur" -gt "$last_count" ]; then
        last_count="$cur"
        since="$(date +%s)"
        continue
      fi
      idle=$(( $(date +%s) - since ))
      if [ "$idle" -ge "$limit_secs" ]; then
        printf '%s\n' "$idle" > "$stamp.stalled"
        if [ -f "$stamp.pid" ]; then
          target_pid="$(cat "$stamp.pid" 2>/dev/null || true)"
          if [ -n "$target_pid" ]; then
            fallback_kill_tree "$target_pid" TERM
            sleep 1
            fallback_kill_tree "$target_pid" KILL
          fi
        fi
        exit 0
      fi
    done
  ) </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!"
}

fallback_watchdog_stop() {
  local wd_pid="$1" stamp="$2"
  : > "$stamp.done"
  fallback_kill_tree "$wd_pid" TERM
  wait "$wd_pid" 2>/dev/null || true
}
