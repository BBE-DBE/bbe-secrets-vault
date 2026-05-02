#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-rotate.sh — rotate preserves plaintext, changes ciphertext on
# disk. SKIPS when age is missing.
set -u

failures=0
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$toolkit_dir/secrets-vault.sh"
sandbox="/tmp/svtest-rot-$$"
export BBE_VAULT_HOME="$sandbox/vault"
export BBE_VAULT_ACTOR="rotate-test"

cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1 \
   || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-rotate: age or jq missing"
  exit 77
fi

mkdir -p "$sandbox"

check() {
  local name="$1"; shift
  if "$@"; then echo "PASS test-rotate: $name"
  else echo "FAIL test-rotate: $name"; failures=$((failures + 1))
  fi
}

bash "$cli" init >/dev/null 2>&1
printf 'rotate-me' | bash "$cli" set rotkey --stdin >/dev/null 2>&1

check_rotate_preserves_plaintext() {
  local before after
  before="$(bash "$cli" get rotkey 2>/dev/null)"
  bash "$cli" rotate rotkey >/dev/null 2>&1 || return 1
  after="$(bash "$cli" get rotkey 2>/dev/null)"
  [[ "$before" == "$after" && "$after" == "rotate-me" ]]
}

check_rotate_changes_ciphertext_bytes() {
  local before_hash after_hash
  before_hash="$(sha256sum "$BBE_VAULT_HOME/secrets.d/rotkey.age" | awk '{print $1}')"
  bash "$cli" rotate rotkey >/dev/null 2>&1 || return 1
  after_hash="$(sha256sum "$BBE_VAULT_HOME/secrets.d/rotkey.age" | awk '{print $1}')"
  # age uses ephemeral X25519 share keys per encryption; the
  # ciphertext bytes WILL differ even when re-encrypting the same
  # plaintext with the same identity.
  [[ "$before_hash" != "$after_hash" ]]
}

check_rotate_unknown_exits_66() {
  local rc
  set +e
  bash "$cli" rotate does-not-exist >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 66 ]]
}

check_rotate_appends_audit_event() {
  local before after
  before="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  bash "$cli" rotate rotkey >/dev/null 2>&1 || return 1
  after="$(wc -l <"$BBE_VAULT_HOME/audit.jsonl")"
  [[ "$after" -gt "$before" ]]
}

check "rotate preserves the plaintext value" check_rotate_preserves_plaintext
check "rotate changes the ciphertext bytes on disk" check_rotate_changes_ciphertext_bytes
check "rotate on unknown secret exits 66" check_rotate_unknown_exits_66
check "rotate appends an audit event" check_rotate_appends_audit_event

if [[ "$failures" -eq 0 ]]; then
  echo "PASS test-rotate: all checks passed"
else
  echo "FAIL test-rotate: $failures failing checks"
fi

exit "$failures"
