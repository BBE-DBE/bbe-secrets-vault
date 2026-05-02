#!/usr/bin/env bash
# shellcheck disable=SC1091
# vault-lib/rotate.sh — `secrets-vault.sh rotate <name>` implementation.
# Re-encrypts a secret in place under the current vault identity.
#
# v0.1.0 semantics: "rotate" rewrites the .age file with a fresh
# encryption envelope (new ephemeral X25519 share key per age's normal
# operation) using the same identity. The ciphertext shape changes;
# the plaintext is preserved verbatim.
#
# This is most useful AFTER a vault re-init (--force) when older
# secrets need to be re-encrypted to the new identity. For that flow:
#   1. secrets-vault.sh init --force                  # new identity
#   2. # rename old identity backup to identity.txt   # temporarily restore
#   3. for s in $(secrets-vault.sh list); do
#         secrets-vault.sh rotate "$s"
#      done
# A future v0.2.0 will package this as `rotate --all-after-rekey`.
#
# Usage:
#   rotate <name>
#
# Exit codes:
#   0   ok
#   1   age missing / encryption / decryption failed
#   64  usage error
#   65  vault not initialised
#   66  named secret does not exist
#
# License: MIT.

set -euo pipefail

# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
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

[[ -n "$name" ]] || vault_die 64 "rotate requires a secret name"
vault_validate_secret_name "$name"
vault_require_age
vault_require_jq
vault_require_initialized

src="$(vault_secret_path "$name")"
[[ -f "$src" ]] || vault_die 66 "no such secret: $name"

# Decrypt to temp file, re-encrypt to a tmp ciphertext, then atomic-mv.
# The temp file is created with mktemp (mode 0600) so the plaintext is
# never visible to other users. Cleanup on every exit path.
tmp_plain="$(mktemp)"
tmp_cipher="$(mktemp)"
chmod 0600 "$tmp_plain" "$tmp_cipher"
cleanup() { rm -f "$tmp_plain" "$tmp_cipher"; }
trap cleanup EXIT

age -d -i "$IDENTITY_FILE" "$src" >"$tmp_plain"
[[ -s "$tmp_plain" ]] || vault_die 1 "decryption produced empty plaintext for $name (corrupt secret?)"

age -e -R "$RECIPIENTS_FILE" -o "$tmp_cipher" <"$tmp_plain"

old_size="$(wc -c <"$src" | tr -d ' ')"
new_size="$(wc -c <"$tmp_cipher" | tr -d ' ')"

mv "$tmp_cipher" "$src"
chmod 0600 "$src"
# Best-effort wipe of the plaintext temp file before unlink.
dd if=/dev/zero of="$tmp_plain" bs=1 count="$(wc -c <"$tmp_plain" | tr -d ' ')" 2>/dev/null || true
rm -f "$tmp_plain"
trap - EXIT

vault_audit "rotate" "$name" "$(jq -cn --argjson o "$old_size" --argjson n "$new_size" '{old_ciphertext_bytes: $o, new_ciphertext_bytes: $n}')"

printf 'secrets-vault: rotated %s (ciphertext %s -> %s bytes)\n' "$name" "$old_size" "$new_size"
