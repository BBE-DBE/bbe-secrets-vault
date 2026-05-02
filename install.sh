#!/usr/bin/env bash
# install.sh — dependency check + first-run pointer for bbe-secrets-vault.
#
# Does NOT mutate ~/.bbe-vault/ — that's `secrets-vault.sh init`'s job.
# This script just verifies prerequisites and prints the next step.
#
# Usage:
#   install.sh          # check deps, print next step
#   install.sh --check  # only check deps, exit 0/1
#
# Exit codes:
#   0   prerequisites satisfied
#   1   age binary missing
#   2   jq missing (audit log writer)
#   64  usage error
#
# License: MIT.

set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_VERSION="$(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || printf '0.0.0')"

mode="hint"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   mode="check" ;;
    --version) printf '%s\n' "$TOOLKIT_VERSION"; exit 0 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) printf 'install: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
  shift
done

info()  { printf 'install: %s\n' "$*"; }
warn()  { printf 'install: %s\n' "$*" >&2; }
fail()  { local code="$1"; shift; printf 'install: %s\n' "$*" >&2; exit "$code"; }

# Detect the package manager and emit the right install line.
age_install_hint() {
  if command -v brew >/dev/null 2>&1; then
    printf '  brew install age\n'
  elif command -v apt-get >/dev/null 2>&1; then
    printf '  sudo apt install age\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf '  sudo dnf install age\n'
  elif command -v pacman >/dev/null 2>&1; then
    printf '  sudo pacman -S age\n'
  elif command -v apk >/dev/null 2>&1; then
    printf '  sudo apk add age\n'
  else
    printf '  https://github.com/FiloSottile/age#installation\n'
  fi
}

if ! command -v age >/dev/null 2>&1; then
  warn "age is not installed. bbe-secrets-vault requires age for at-rest encryption."
  warn "Install age via your package manager:"
  age_install_hint >&2
  exit 1
fi

if ! command -v age-keygen >/dev/null 2>&1; then
  fail 1 "age is installed but age-keygen is missing. Install the full age package."
fi

if ! command -v jq >/dev/null 2>&1; then
  fail 2 "jq is required for the audit log. Install jq via your package manager."
fi

age_version="$(age --version 2>/dev/null || printf 'unknown')"

if [[ "$mode" == "check" ]]; then
  info "OK — age=$age_version, jq present, toolkit=$TOOLKIT_VERSION"
  exit 0
fi

info "OK — bbe-secrets-vault $TOOLKIT_VERSION prerequisites satisfied:"
info "  age:     $age_version"
info "  jq:      $(jq --version 2>/dev/null || printf 'unknown')"
info ""
info "Next step:"
info "  $TOOLKIT_DIR/secrets-vault.sh init"
info ""
info "(or set BBE_VAULT_HOME=/path/to/somewhere first to use a non-default location)"
