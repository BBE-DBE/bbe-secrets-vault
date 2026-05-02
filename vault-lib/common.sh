#!/usr/bin/env bash
# vault-lib/common.sh — shared helpers for every subcommand.
# Sourced; never executed directly. Keeps vault-path resolution,
# audit-log writes, and dependency checks in one place.
#
# License: MIT.

# Default vault location. BBE_VAULT_HOME overrides — used by tests
# and for per-tenant vaults (one vault per env).
VAULT_HOME="${BBE_VAULT_HOME:-$HOME/.bbe-vault}"
IDENTITY_FILE="$VAULT_HOME/identity.txt"
RECIPIENTS_FILE="$VAULT_HOME/recipients.txt"
SECRETS_DIR="$VAULT_HOME/secrets.d"
AUDIT_FILE="$VAULT_HOME/audit.jsonl"

# Allowed character class for secret names. Restrictive on purpose —
# names become filenames; arbitrary input would let a typo hop the
# secrets.d/ boundary or collide with hidden files.
SECRET_NAME_RE='^[a-z0-9][a-z0-9._-]{0,63}$'

vault_die() {
  local code="$1"; shift
  printf 'secrets-vault: %s\n' "$*" >&2
  exit "$code"
}

vault_require_cmd() {
  command -v "$1" >/dev/null 2>&1 \
    || vault_die 1 "missing required tool: $1"
}

vault_require_age() {
  vault_require_cmd age
  vault_require_cmd age-keygen
}

vault_require_jq() {
  vault_require_cmd jq
}

vault_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

vault_validate_secret_name() {
  local name="$1"
  [[ "$name" =~ $SECRET_NAME_RE ]] \
    || vault_die 64 "invalid secret name '$name' — must match $SECRET_NAME_RE"
}

vault_require_initialized() {
  [[ -d "$VAULT_HOME" ]] || vault_die 65 "vault not initialised at $VAULT_HOME (run: secrets-vault.sh init)"
  [[ -f "$IDENTITY_FILE" ]] || vault_die 65 "identity missing at $IDENTITY_FILE — vault is corrupt"
  [[ -f "$RECIPIENTS_FILE" ]] || vault_die 65 "recipients missing at $RECIPIENTS_FILE — vault is corrupt"
  [[ -d "$SECRETS_DIR" ]] || mkdir -p "$SECRETS_DIR"
}

# vault_audit <action> <secret_name> [extra_json_fragment]
# Appends one JSONL event. Caller can pass an extra raw JSON object
# fragment merged into the payload (e.g. '{"old_size":42}'). Never
# truncates; only `>>` is used here.
vault_audit() {
  local action="$1"
  local name="${2:-}"
  local extra="${3:-{\}}"
  local actor="${BBE_VAULT_ACTOR:-${USER:-unknown}}"
  local pid="$$"
  local ts
  ts="$(vault_iso_now)"
  vault_require_jq

  mkdir -p "$VAULT_HOME"
  jq -cn \
    --arg ts "$ts" \
    --arg action "$action" \
    --arg name "$name" \
    --arg actor "$actor" \
    --argjson pid "$pid" \
    --argjson extra "$extra" \
    '{
      timestamp: $ts,
      action: $action,
      secret_name: (if $name == "" then null else $name end),
      actor: $actor,
      pid: $pid
    } + $extra' >>"$AUDIT_FILE"
  # Tighten perms; harmless if already correct.
  chmod 0600 "$AUDIT_FILE" 2>/dev/null || true
}

# vault_secret_path <name> — echoes the path of the .age file.
vault_secret_path() {
  printf '%s/%s.age' "$SECRETS_DIR" "$1"
}
