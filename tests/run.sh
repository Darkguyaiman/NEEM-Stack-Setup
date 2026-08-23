#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$TEST_DIR/test-unix.sh"

if command -v pwsh >/dev/null 2>&1; then
  printf '\n=== Static project validation ===\n'
  pwsh -NoProfile -File "$TEST_DIR/validate.ps1"
else
  printf '\nPowerShell is unavailable; Windows-specific suites were not run.\n'
fi
