#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/init.sh — `secrets-vault.sh init` implementation.
# Creates ~/.bbe-vault/ (or $BBE_VAULT_HOME) with identity.txt,
# recipients.txt and secrets.d/. Idempotent: a second run reports
# the existing vault and exits 0.
#
# Usage:
#   init [--force]   # --force overwrites an existing identity (DESTRUCTIVE)
#
# Exit codes:
#   0  ok / already-initialised
#   1  age missing
#   2  vault exists and --force NOT given (defensive default)
#   64 usage error
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=1 ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) vault_die 64 "unknown argument: $1" ;;
  esac
  shift
done

vault_require_age
vault_require_jq

# Idempotent path: existing vault, no --force → success no-op.
if [[ -f "$IDENTITY_FILE" && -f "$RECIPIENTS_FILE" ]]; then
  if [[ "$force" -eq 0 ]]; then
    printf 'secrets-vault: vault already initialised at %s\n' "$VAULT_HOME"
    printf 'secrets-vault: (use --force to regenerate the identity — DESTROYS access to existing secrets)\n'
    vault_audit "init_noop" "" '{"already_initialized":true}'
    exit 0
  fi
  printf 'secrets-vault: --force given; backing up existing identity before regenerating\n' >&2
  backup="$IDENTITY_FILE.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$IDENTITY_FILE" "$backup"
  cp -a "$RECIPIENTS_FILE" "$RECIPIENTS_FILE.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  printf 'secrets-vault: identity backup at %s\n' "$backup" >&2
fi

mkdir -p "$VAULT_HOME" "$SECRETS_DIR"
chmod 0700 "$VAULT_HOME" "$SECRETS_DIR" 2>/dev/null || true

# age-keygen writes the private key plus a "# public key:" comment
# to stdout. Use stdout-redirect (not -o) because age-keygen's -o
# refuses to overwrite an existing file — and mktemp creates one,
# so the two collide. Use mktemp -u (don't create) for a unique
# name, write directly via stdout, then mv into place atomically.
tmp_identity="$(mktemp -u)"
trap 'rm -f "$tmp_identity"' EXIT
age-keygen 2>/dev/null >"$tmp_identity"
[[ -s "$tmp_identity" ]] || vault_die 1 "age-keygen produced empty output"

mv "$tmp_identity" "$IDENTITY_FILE"
chmod 0600 "$IDENTITY_FILE"
trap - EXIT

# Derive public key (recipient) from the identity.
public_key="$(grep -E '^# public key:' "$IDENTITY_FILE" | head -n1 | sed -E 's/^# public key: //')"
[[ -n "$public_key" ]] || vault_die 1 "could not derive public key from generated identity"
printf '%s\n' "$public_key" >"$RECIPIENTS_FILE"
chmod 0644 "$RECIPIENTS_FILE"

vault_audit "init" "" "$(jq -cn --arg pk "$public_key" '{public_key: $pk, force: '"$force"'}')"

printf 'secrets-vault: initialised %s\n' "$VAULT_HOME"
printf 'secrets-vault:   identity   = %s (mode 0600)\n' "$IDENTITY_FILE"
printf 'secrets-vault:   recipients = %s\n' "$RECIPIENTS_FILE"
printf 'secrets-vault:   public key = %s\n' "$public_key"
printf 'secrets-vault: BACK UP %s SOMEWHERE SAFE — losing it loses every secret.\n' "$IDENTITY_FILE"
