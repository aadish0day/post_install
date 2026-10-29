#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Intel Hardware & Drivers (Debian/Ubuntu)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

command -v debconf-set-selections >/dev/null 2>&1 || apt_install debconf-utils
if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "intel-microcode intel-microcode/initramfs note" | $SUDO debconf-set-selections 2>/dev/null || true
fi

# Delegate to GPU/CPU driver script
if [ -f "$SCRIPT_DIR/gpu/intel.sh" ]; then
    bash "$SCRIPT_DIR/gpu/intel.sh"
fi
