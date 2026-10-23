#!/usr/bin/env bash
set -euo pipefail

# Kali wrapper for Debian advcpmv installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec bash "$REPO_ROOT/debian/apps/advcpmv.sh" "$@"
