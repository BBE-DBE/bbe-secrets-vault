#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/list.sh — `secrets-vault.sh list` implementation.
# Prints one secret name per line. Never prints values.
#
# Usage:
#   list             # one name per line, sorted, no values
#   list --json      # JSON array of {name, size_bytes, mtime}
#
# Exit codes:
#   0   ok (zero-secret vault is OK)
#   65  vault not initialised
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode="plain"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) mode="json" ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) vault_die 64 "unknown argument: $1" ;;
  esac
  shift
done

vault_require_initialized

# list does NOT touch age — purely filesystem; safe with age absent.
shopt -s nullglob
files=("$SECRETS_DIR"/*.age)

if [[ "$mode" == "plain" ]]; then
  for f in "${files[@]}"; do
    base="$(basename "$f" .age)"
    printf '%s\n' "$base"
  done | sort
  exit 0
fi

# JSON mode
vault_require_jq
{
  printf '['
  first=1
  for f in "${files[@]}"; do
    base="$(basename "$f" .age)"
    size="$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f")"
    mtime="$(date -u -r "$f" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
            || date -u -d "@$(stat -c '%Y' "$f")" +%Y-%m-%dT%H:%M:%SZ)"
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    jq -cn --arg n "$base" --argjson s "$size" --arg m "$mtime" \
      '{name: $n, size_bytes: $s, mtime: $m}'
  done | sort
  printf ']\n'
}

vault_audit "list" "" "$(jq -cn --argjson n "${#files[@]}" '{count: $n}')"
