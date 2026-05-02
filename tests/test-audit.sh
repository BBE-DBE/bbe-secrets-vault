#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-audit.sh — every operation appends one JSONL event; no code
# path uses `>` to overwrite the log; secret values never appear
# in the log. SKIPS when age missing.
set -u

failures=0
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$toolkit_dir/secrets-vault.sh"
sandbox="/tmp/svtest-aud-$$"
export BBE_VAULT_HOME="$sandbox/vault"
export BBE_VAULT_ACTOR="audit-test"

cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1 \
   || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-audit: age or jq missing"
  exit 77
fi

mkdir -p "$sandbox"

check() {
  local name="$1"; shift
  if "$@"; then echo "PASS test-audit: $name"
  else echo "FAIL test-audit: $name"; failures=$((failures + 1))
  fi
}

bash "$cli" init >/dev/null 2>&1

check_init_writes_audit_event() {
  jq -e 'select(.action == "init") | true' "$BBE_VAULT_HOME/audit.jsonl" >/dev/null
}

check_set_writes_audit_event() {
  local before after
  before="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  printf 'aud-secret' | bash "$cli" set audkey --stdin >/dev/null 2>&1 || return 1
  after="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  [[ "$after" -gt "$before" ]] || return 1
  tail -n1 "$BBE_VAULT_HOME/audit.jsonl" | jq -e 'select(.action == "set" and .secret_name == "audkey")' >/dev/null
}

check_get_writes_audit_event() {
  local before after
  before="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  bash "$cli" get audkey >/dev/null 2>&1 || return 1
  after="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  [[ "$after" -gt "$before" ]] || return 1
  tail -n1 "$BBE_VAULT_HOME/audit.jsonl" | jq -e 'select(.action == "get" and .secret_name == "audkey")' >/dev/null
}

check_audit_log_never_contains_secret_value() {
  ! grep -q 'aud-secret' "$BBE_VAULT_HOME/audit.jsonl"
}

check_audit_event_has_iso_timestamp() {
  local last_ts
  last_ts="$(tail -n1 "$BBE_VAULT_HOME/audit.jsonl" | jq -r '.timestamp')"
  [[ "$last_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

check_audit_event_carries_actor() {
  local actor
  actor="$(tail -n1 "$BBE_VAULT_HOME/audit.jsonl" | jq -r '.actor')"
  [[ "$actor" == "audit-test" ]]
}

check_audit_subcommand_pretty_lists() {
  local out
  out="$(bash "$cli" audit --tail 2 2>/dev/null)" || return 1
  printf '%s' "$out" | head -n1 | grep -q 'TIMESTAMP'
}

check_audit_subcommand_json_emits_jsonl() {
  local out
  out="$(bash "$cli" audit --json --tail 1 2>/dev/null)" || return 1
  printf '%s' "$out" | jq -e 'type == "object"' >/dev/null
}

check_audit_since_filter_works() {
  # All events produced today should be returned by --since today;
  # a far-future filter returns nothing.
  local today_count future_count
  today_count="$(bash "$cli" audit --since 2026-01-01 --json 2>/dev/null | wc -l)"
  future_count="$(bash "$cli" audit --since 9999-01-01 --json 2>/dev/null | wc -l)"
  [[ "$today_count" -gt 0 && "$future_count" -eq 0 ]]
}

check_audit_log_is_append_only_in_codepaths() {
  # Static check: no `> $AUDIT_FILE` or `> "$AUDIT_FILE"` anywhere
  # in the lib (single-`>` = overwrite). Only `>>` (append) allowed
  # for the audit file. Use Perl regex with negative lookbehind to
  # match `>` NOT preceded by another `>`.
  # shellcheck disable=SC2016 # regex with literal `\$`, NOT a shell var
  ! grep -nP '(?<!>)>\s*"?\$AUDIT_FILE' "$toolkit_dir/vault-lib/"*.sh
}

check_audit_log_permissions_0600() {
  local mode
  mode="$(stat -c '%a' "$BBE_VAULT_HOME/audit.jsonl" 2>/dev/null || stat -f '%A' "$BBE_VAULT_HOME/audit.jsonl")"
  [[ "$mode" == "600" ]]
}

check "init writes one audit event" check_init_writes_audit_event
check "set writes an audit event with secret_name" check_set_writes_audit_event
check "get writes an audit event with secret_name" check_get_writes_audit_event
check "audit log NEVER contains the secret value" check_audit_log_never_contains_secret_value
check "audit event carries ISO-8601 UTC Z timestamp" check_audit_event_has_iso_timestamp
check "audit event carries the BBE_VAULT_ACTOR" check_audit_event_carries_actor
check "audit subcommand pretty mode emits header" check_audit_subcommand_pretty_lists
check "audit --json emits JSON objects" check_audit_subcommand_json_emits_jsonl
check "audit --since filters as expected" check_audit_since_filter_works
check "no code path overwrites the audit log (only >> appends)" check_audit_log_is_append_only_in_codepaths
check "audit log permissions are 0600" check_audit_log_permissions_0600

if [[ "$failures" -eq 0 ]]; then
  echo "PASS test-audit: all checks passed"
else
  echo "FAIL test-audit: $failures failing checks"
fi

exit "$failures"
