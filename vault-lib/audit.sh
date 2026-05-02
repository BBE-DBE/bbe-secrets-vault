#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/audit.sh — `secrets-vault.sh audit` implementation.
# Streams the audit log to stdout, optionally filtered by date.
#
# Usage:
#   audit                         # all events, oldest first
#   audit --since YYYY-MM-DD      # ISO date or full ISO-8601 timestamp
#   audit --tail N                # last N events
#   audit --action <action>       # filter by action (set|get|list|...)
#   audit --json                  # raw JSONL (default is pretty-print)
#
# Exit codes:
#   0   ok (empty log is OK)
#   65  vault not initialised
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

since=""
tail_n=""
action_filter=""
mode="pretty"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)  shift; since="$1" ;;
    --tail)   shift; tail_n="$1" ;;
    --action) shift; action_filter="$1" ;;
    --json)   mode="json" ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) vault_die 64 "unknown argument: $1" ;;
  esac
  shift
done

vault_require_initialized
vault_require_jq

if [[ ! -f "$AUDIT_FILE" ]]; then
  exit 0
fi

# Compose the jq filter: optional --since (lex-sortable ISO),
# optional --action (string equality).
filter='.'
if [[ -n "$since" ]]; then
  # Allow date-only (YYYY-MM-DD); pad with T00:00:00Z so lex compare works.
  if [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    since="${since}T00:00:00Z"
  fi
  filter+=" | select(.timestamp >= \"$since\")"
fi
if [[ -n "$action_filter" ]]; then
  filter+=" | select(.action == \"$action_filter\")"
fi

if [[ -n "$tail_n" ]]; then
  filtered="$(jq -c "$filter" "$AUDIT_FILE" | tail -n "$tail_n")"
else
  filtered="$(jq -c "$filter" "$AUDIT_FILE")"
fi

if [[ "$mode" == "json" ]]; then
  # Suppress trailing-newline-only output when the filter matched
  # nothing — a bare newline would inflate `wc -l` to 1 and confuse
  # consumers who count "events seen" via line count.
  [[ -n "$filtered" ]] && printf '%s\n' "$filtered"
  exit 0
fi

# Pretty-print: one human-readable line per event, no values ever.
printf '%-22s  %-10s  %-30s  %s\n' "TIMESTAMP" "ACTION" "SECRET_NAME" "ACTOR"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  ts="$(printf '%s' "$line" | jq -r '.timestamp')"
  action="$(printf '%s' "$line" | jq -r '.action')"
  sname="$(printf '%s' "$line" | jq -r '.secret_name // "-"')"
  actor="$(printf '%s' "$line" | jq -r '.actor // "-"')"
  printf '%-22s  %-10s  %-30s  %s\n' "$ts" "$action" "$sname" "$actor"
done <<<"$filtered"
