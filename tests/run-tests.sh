#!/usr/bin/env bash
# Roda a suite inteira (test-*.sh) e resume COMMAND/EXIT/RESULT por arquivo.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

for t in "$ROOT"/tests/test-*.sh; do
  name="$(basename "$t")"
  printf '\n=== %s ===\n' "$name"
  if bash "$t"; then
    printf 'PASS %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL %s (exit %s)\n' "$name" "$?"
    fail=$((fail + 1))
  fi
done

printf '\nRESULT: %s passaram, %s falharam\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
