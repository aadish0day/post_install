#!/usr/bin/env bash
# ============================================================================
# Arch Linux Burp Suite Professional Installer Wrapper
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared Burp installer
# shellcheck source=lib/burp-install.sh
source "$ROOT_DIR/lib/burp-install.sh"

distro_install_deps() {
    echo "Installing Arch Linux dependencies for Burp Suite..."
    if ! command -v java &>/dev/null || ! command -v curl &>/dev/null || ! command -v aria2c &>/dev/null || ! command -v openssl &>/dev/null || ! command -v certutil &>/dev/null; then
        sudo pacman -S --noconfirm --needed jdk21-openjdk wget curl aria2 openssl ca-certificates ca-certificates-utils nss
        echo "Setting Java 21 as default..."
        sudo archlinux-java set java-21-openjdk 2>/dev/null || sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk/bin/java 2>/dev/null || true
    else
        echo "Dependencies already satisfied (java, curl, aria2 present)."
    fi
}

distro_sandbox_check() {
    burp_check_user_namespaces
}

run_burp_installation "Arch Linux" distro_install_deps distro_sandbox_check "$@"
