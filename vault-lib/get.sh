#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/get.sh — `secrets-vault.sh get <name>` implementation.
# Decrypts <name>.age via the vault identity and writes the
# plaintext to stdout. Audit log records the access.
#
# When stdout is a TTY, prints a one-line warning to stderr first
# ("(printing secret to terminal — pipe to consume safely)") so a
# casual operator notices the leak surface. Pipes do not warn.
#
# Usage:
#   get <name>          # plaintext to stdout
#   get <name> --quiet  # suppress the TTY warning
#
# Exit codes:
#   0   ok (plaintext written to stdout)
#   1   age missing / decryption failed
#   64  usage error
#   65  vault not initialised
#   66  named secret does not exist
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name=""
quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) quiet=1 ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
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

[[ -n "$name" ]] || vault_die 64 "get requires a secret name"
vault_validate_secret_name "$name"
vault_require_age
vault_require_jq
vault_require_initialized

src="$(vault_secret_path "$name")"
[[ -f "$src" ]] || vault_die 66 "no such secret: $name"

if [[ "$quiet" -eq 0 && -t 1 ]]; then
  printf 'secrets-vault: (printing secret %s to terminal — pipe to consume safely)\n' "$name" >&2
fi

age -d -i "$IDENTITY_FILE" "$src"
rc=$?

vault_audit "get" "$name" "$(jq -cn --argjson rc "$rc" --argjson tty "$([[ -t 1 ]] && echo true || echo false)" '{exit_code: $rc, stdout_was_tty: $tty}')"

exit "$rc"
