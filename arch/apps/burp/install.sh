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
    echo "Configuring dependencies and Java 21 for Burp Suite (Arch Linux)..."

    # 1. Ensure jdk21-openjdk is installed
    if ! pacman -Qi jdk21-openjdk &>/dev/null; then
        echo "Installing OpenJDK 21..."
        sudo pacman -S --noconfirm --needed jdk21-openjdk
    fi

    # 2. Always set Java 21 as default JVM
    if command -v archlinux-java &>/dev/null; then
        echo "Setting Java 21 as default JVM..."
        sudo archlinux-java set java-21-openjdk 2>/dev/null || true
    fi

    # 3. Ensure required network and SSL tools
    local missing_tools=()
    for tool in wget curl aria2c openssl certutil; do
        if ! command -v "$tool" &>/dev/null; then
            case "$tool" in
                aria2c) missing_tools+=(aria2) ;;
                certutil) missing_tools+=(nss) ;;
                *) missing_tools+=("$tool") ;;
            esac
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        sudo pacman -S --noconfirm --needed "${missing_tools[@]}" ca-certificates ca-certificates-utils
    fi
}

distro_sandbox_check() {
    burp_check_user_namespaces
}

run_burp_installation "Arch Linux" distro_install_deps distro_sandbox_check "$@"
