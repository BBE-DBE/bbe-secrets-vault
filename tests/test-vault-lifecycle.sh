#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-vault-lifecycle.sh — init / set / get / list end-to-end.
# Requires `age` and `age-keygen`; SKIPS (exit 77) when missing.
set -u

failures=0
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$toolkit_dir/secrets-vault.sh"
sandbox="/tmp/svtest-life-$$"
export BBE_VAULT_HOME="$sandbox/vault"
export BBE_VAULT_ACTOR="lifecycle-test"

cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
  echo "SKIP test-vault-lifecycle: age binary not installed (install via apt/brew/dnf age)"
  exit 77
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-vault-lifecycle: jq not installed"
  exit 77
fi

check() {
  local name="$1"; shift
  if "$@"; then echo "PASS test-vault-lifecycle: $name"
  else echo "FAIL test-vault-lifecycle: $name"; failures=$((failures + 1))
  fi
}

mkdir -p "$sandbox"

check_init_creates_layout() {
  bash "$cli" init >/dev/null 2>&1 || return 1
  [[ -f "$BBE_VAULT_HOME/identity.txt" ]] || return 1
  [[ -f "$BBE_VAULT_HOME/recipients.txt" ]] || return 1
  [[ -d "$BBE_VAULT_HOME/secrets.d" ]] || return 1
  [[ -f "$BBE_VAULT_HOME/audit.jsonl" ]] || return 1
  # Identity file must be 0600.
  local mode
  mode="$(stat -c '%a' "$BBE_VAULT_HOME/identity.txt" 2>/dev/null || stat -f '%A' "$BBE_VAULT_HOME/identity.txt")"
  [[ "$mode" == "600" ]]
}

check_init_idempotent() {
  bash "$cli" init >/dev/null 2>&1 || return 1
  # Second run must not regenerate; capture identity hash before/after.
  local before after
  before="$(sha256sum "$BBE_VAULT_HOME/identity.txt" | awk '{print $1}')"
  bash "$cli" init >/dev/null 2>&1 || return 1
  after="$(sha256sum "$BBE_VAULT_HOME/identity.txt" | awk '{print $1}')"
  [[ "$before" == "$after" ]]
}

check_set_then_get_roundtrip() {
  printf 'super-secret-value-XYZ' | bash "$cli" set test-key --stdin >/dev/null 2>&1 || return 1
  local out
  out="$(bash "$cli" get test-key 2>/dev/null)"
  [[ "$out" == "super-secret-value-XYZ" ]]
}

check_get_unknown_exits_66() {
  local rc
  set +e
  bash "$cli" get does-not-exist >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 66 ]]
}

check_list_shows_names_only() {
  printf 'value-a' | bash "$cli" set alpha --stdin >/dev/null 2>&1 || return 1
  printf 'value-b' | bash "$cli" set beta --stdin >/dev/null 2>&1 || return 1
  local out
  out="$(bash "$cli" list 2>/dev/null)"
  printf '%s' "$out" | grep -q '^alpha$' || return 1
  printf '%s' "$out" | grep -q '^beta$' || return 1
  # Most importantly: values must NOT appear in list output.
  ! printf '%s' "$out" | grep -q 'value-a' || return 1
  ! printf '%s' "$out" | grep -q 'value-b' || return 1
}

check_set_empty_via_stdin_exits_2() {
  local rc
  set +e
  printf '' | bash "$cli" set empty --stdin >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]]
}

check_secret_files_are_0600() {
  printf 'p' | bash "$cli" set perm-check --stdin >/dev/null 2>&1 || return 1
  local mode
  mode="$(stat -c '%a' "$BBE_VAULT_HOME/secrets.d/perm-check.age" 2>/dev/null || stat -f '%A' "$BBE_VAULT_HOME/secrets.d/perm-check.age")"
  [[ "$mode" == "600" ]]
}

check_recipients_is_public_key() {
  # recipients.txt should be a single line starting with "age1".
  local line
  line="$(head -n1 "$BBE_VAULT_HOME/recipients.txt")"
  [[ "$line" =~ ^age1 ]]
}

check "init creates layout with 0600 identity" check_init_creates_layout
check "init is idempotent (does not regenerate identity)" check_init_idempotent
check "set + get round-trips a secret value byte-identical" check_set_then_get_roundtrip
check "get on unknown secret exits 66" check_get_unknown_exits_66
check "list prints names only, never values" check_list_shows_names_only
check "set --stdin with empty value exits 2" check_set_empty_via_stdin_exits_2
check "stored .age files are mode 0600" check_secret_files_are_0600
check "recipients.txt is the derived age public key" check_recipients_is_public_key

if [[ "$failures" -eq 0 ]]; then
  echo "PASS test-vault-lifecycle: all checks passed"
else
  echo "FAIL test-vault-lifecycle: $failures failing checks"
fi

exit "$failures"
