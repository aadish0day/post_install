#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Desktop Theme and Fonts Configuration (Debian/Ubuntu)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

command -v debconf-set-selections >/dev/null 2>&1 || apt_install debconf-utils
if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | $SUDO debconf-set-selections 2>/dev/null || true
fi

apt_install papirus-icon-theme fonts-noto fonts-noto-color-emoji fonts-jetbrains-mono
