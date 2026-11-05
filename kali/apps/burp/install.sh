#!/usr/bin/env bash
# ============================================================================
# Kali Linux Burp Suite Professional Installer Wrapper
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared Burp installer
# shellcheck source=lib/burp-install.sh
source "$ROOT_DIR/lib/burp-install.sh"

distro_install_deps() {
    echo "Installing Kali Linux dependencies for Burp Suite..."
    if ! command -v java &>/dev/null || ! command -v wget &>/dev/null || ! command -v curl &>/dev/null || ! command -v certutil &>/dev/null; then
        if command -v nala &>/dev/null; then
            sudo nala install -y openjdk-21-jre wget curl libnss3-tools
        else
            sudo apt update -qq && sudo apt install -y openjdk-21-jre wget curl libnss3-tools
        fi
        echo "Setting Java 21 as default..."
        sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 2>/dev/null || true
    else
        echo "Dependencies already satisfied (java, wget, curl present)."
    fi
}

distro_sandbox_check() {
    burp_enable_debian_userns
}

run_burp_installation "Kali Linux" distro_install_deps distro_sandbox_check "$@"
