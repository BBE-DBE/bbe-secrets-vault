#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-cli-surface.sh — argument-parsing tests that DO NOT need age.
# Always runs; never skips.
set -u

failures=0
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$toolkit_dir/secrets-vault.sh"
sandbox="/tmp/svtest-cli-$$"
mkdir -p "$sandbox"
trap 'rm -rf "$sandbox"' EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-cli-surface: $name"
  else
    echo "FAIL test-cli-surface: $name"
    failures=$((failures + 1))
  fi
}

check_no_args_exits_64() {
  local rc
  set +e
  bash "$cli" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]]
}

check_unknown_subcommand_exits_64() {
  local rc
  set +e
  bash "$cli" banana >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]]
}

check_version_flag() {
  local v expected
  v="$(bash "$cli" --version 2>/dev/null)"
  expected="$(cat "$toolkit_dir/VERSION")"
  [[ "$v" == "$expected" ]]
}

check_help_flag_exits_zero() {
  bash "$cli" --help >/dev/null 2>&1
}

check_install_check_reports() {
  local rc
  set +e
  bash "$toolkit_dir/install.sh" --check >/dev/null 2>&1
  rc=$?
  set -e
  # 0 if age + jq present; 1 if age missing; 2 if jq missing.
  [[ "$rc" -eq 0 || "$rc" -eq 1 || "$rc" -eq 2 ]]
}

check_install_emits_install_hint_when_age_missing() {
  if command -v age >/dev/null 2>&1; then
    # age is present — skip this check (not applicable on this host).
    return 0
  fi
  local out
  out="$(bash "$toolkit_dir/install.sh" 2>&1)" || true
  printf '%s' "$out" | grep -Eq 'install age|brew install age|apt install age|dnf install age'
}

check_set_without_name_exits_64() {
  local rc
  set +e
  BBE_VAULT_HOME="$sandbox/v" bash "$cli" set >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]]
}

check_set_invalid_name_exits_64() {
  local rc
  set +e
  BBE_VAULT_HOME="$sandbox/v" bash "$cli" set "Bad Name!" </dev/null >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]]
}

check_get_uninitialized_exits_65() {
  local rc
  set +e
  BBE_VAULT_HOME="$sandbox/no-such-vault" bash "$cli" get foo >/dev/null 2>&1
  rc=$?
  set -e
  # If age is missing the missing-tool check (exit 1) fires before
  # the "vault not initialised" check (exit 65). Accept either; the
  # important thing is we never silently print or succeed.
  [[ "$rc" -eq 65 || "$rc" -eq 1 ]]
}

check "no args exits 64" check_no_args_exits_64
check "unknown subcommand exits 64" check_unknown_subcommand_exits_64
check "--version reads VERSION file" check_version_flag
check "--help exits 0" check_help_flag_exits_zero
check "install.sh --check exits 0/1/2" check_install_check_reports
check "install.sh prints install hint when age absent" check_install_emits_install_hint_when_age_missing
check "set without name exits 64" check_set_without_name_exits_64
check "set with invalid name exits 64" check_set_invalid_name_exits_64
check "get on uninitialised vault exits 65 (or 1 if age absent)" check_get_uninitialized_exits_65

if [[ "$failures" -eq 0 ]]; then
  echo "PASS test-cli-surface: all checks passed"
else
  echo "FAIL test-cli-surface: $failures failing checks"
fi

exit "$failures"
