#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/set.sh — `secrets-vault.sh set <name>` implementation.
# Reads the secret from the controlling terminal (input hidden) or
# from stdin when --stdin is given. Writes <name>.age via
# `age -e -R recipients.txt`.
#
# Usage:
#   set <name>            # interactive, terminal echo disabled
#   set <name> --stdin    # read from stdin (single read, trailing
#                           newline preserved if present in input)
#
# Exit codes:
#   0   ok
#   1   age missing / encryption failed
#   2   secret value empty
#   64  usage error
#   65  vault not initialised
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name=""
from_stdin=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stdin) from_stdin=1 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    -*) vault_die 64 "unknown flag: $1" ;;
    *)
      [[ -z "$name" ]] || vault_die 64 "unexpected positional: $1"
      name="$1"
      ;;
  esac
  shift
done

[[ -n "$name" ]] || vault_die 64 "set requires a secret name"
vault_validate_secret_name "$name"
vault_require_age
vault_require_jq
vault_require_initialized

target="$(vault_secret_path "$name")"

if [[ "$from_stdin" -eq 1 ]]; then
  # Read everything from stdin verbatim.
  tmp_in="$(mktemp)"
  trap 'rm -f "$tmp_in"' EXIT
  cat >"$tmp_in"
  bytes=$(wc -c <"$tmp_in" | tr -d ' ')
  [[ "$bytes" -gt 0 ]] || vault_die 2 "empty secret value (--stdin received zero bytes)"
  age -e -R "$RECIPIENTS_FILE" -o "$target" <"$tmp_in"
  rm -f "$tmp_in"
  trap - EXIT
else
  # Interactive: prompt twice, terminal echo off, compare.
  if [[ ! -t 0 ]]; then
    vault_die 64 "stdin is not a terminal; pipe the value with --stdin or run interactively"
  fi
  printf 'Secret value for %s (input hidden): ' "$name" >/dev/tty
  local_value=""
  IFS= read -rs local_value </dev/tty
  printf '\n' >/dev/tty
  [[ -n "$local_value" ]] || vault_die 2 "empty secret value"
  printf 'Confirm: ' >/dev/tty
  confirm=""
  IFS= read -rs confirm </dev/tty
  printf '\n' >/dev/tty
  [[ "$local_value" == "$confirm" ]] || vault_die 2 "secret values did not match"
  # Pipe via process substitution so the value never lands in argv.
  printf '%s' "$local_value" | age -e -R "$RECIPIENTS_FILE" -o "$target"
  unset local_value confirm
fi

chmod 0600 "$target"
vault_audit "set" "$name" "$(jq -cn --argjson b "${bytes:-0}" '{ciphertext_path_only: true}')"

printf 'secrets-vault: stored %s\n' "$name"
