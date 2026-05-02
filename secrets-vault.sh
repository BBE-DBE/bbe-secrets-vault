#!/usr/bin/env bash
# secrets-vault.sh — top-level dispatcher for the bbe-secrets-vault.
# Each subcommand is a script under vault-lib/; this file's only job
# is parsing the subcommand, validating it, and exec'ing the right
# library script with the remaining arguments.
#
# Usage:
#   secrets-vault.sh init [--force]
#   secrets-vault.sh set <name> [--stdin]
#   secrets-vault.sh get <name> [--quiet]
#   secrets-vault.sh list [--json]
#   secrets-vault.sh rotate <name>
#   secrets-vault.sh audit [--since DATE] [--tail N] [--action A] [--json]
#
# Environment:
#   BBE_VAULT_HOME    Override default vault location (~/.bbe-vault).
#   BBE_VAULT_ACTOR   Tag for audit-log "actor" field. Defaults to $USER.
#
# Exit codes:
#   0    success
#   1    runtime failure (age error, jq error, decryption failed, ...)
#   2    invalid input (empty value, mismatched confirm)
#   64   usage error
#   65   vault not initialised / corrupt
#   66   named secret does not exist
#
# License: MIT.

set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_VERSION="$(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || printf '0.0.0')"

usage() {
  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 64
fi

sub="$1"; shift

case "$sub" in
  init|set|get|list|rotate|audit)
    lib="$TOOLKIT_DIR/vault-lib/${sub}.sh"
    if [[ ! -x "$lib" ]]; then
      printf 'secrets-vault: missing or non-executable lib: %s\n' "$lib" >&2
      exit 1
    fi
    exec "$lib" "$@"
    ;;
  --version|-V)
    printf '%s\n' "$TOOLKIT_VERSION"
    exit 0
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    printf 'secrets-vault: unknown subcommand: %s\n\n' "$sub" >&2
    usage >&2
    exit 64
    ;;
esac
