#!/usr/bin/env bash
# run-all.sh — entry point for the test suite.
set -u

failures=0
skipped=0

for test_script in \
  tests/test-cli-surface.sh \
  tests/test-vault-lifecycle.sh \
  tests/test-rotate.sh \
  tests/test-audit.sh
do
  bash "$test_script"
  rc=$?
  case "$rc" in
    0) : ;;
    77) skipped=$((skipped + 1)) ;;  # convention: 77 = SKIP (autotools)
    *) failures=$((failures + 1)) ;;
  esac
done

if [[ "$failures" -eq 0 ]]; then
  if [[ "$skipped" -gt 0 ]]; then
    echo "PASS tests/run-all.sh ($skipped skipped due to missing age)"
  else
    echo "PASS tests/run-all.sh"
  fi
else
  echo "FAIL tests/run-all.sh ($failures failing scripts, $skipped skipped)"
fi

exit "$failures"
