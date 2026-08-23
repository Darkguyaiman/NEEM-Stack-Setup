#!/usr/bin/env bash
# Compatibility entry point. The maintained Unix implementation lives under linux/.

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$PROJECT_DIR/linux/neem.sh" "$@"
