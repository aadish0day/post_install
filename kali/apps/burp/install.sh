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
    echo "Configuring dependencies and Java 21 for Burp Suite (Kali/Debian)..."

    local installer="apt"
    if command -v nala &>/dev/null; then
        installer="nala"
    fi

    # 1. Ensure OpenJDK 21 is installed
    local java_21_installed=false
    if dpkg -l openjdk-21-jre &>/dev/null || dpkg -l openjdk-21-jdk &>/dev/null || [ -d /usr/lib/jvm/java-21-openjdk-amd64 ]; then
        java_21_installed=true
    fi

    if [ "$java_21_installed" = false ]; then
        echo "Installing OpenJDK 21..."
        if [ "$installer" = "nala" ]; then
            sudo nala install -y openjdk-21-jre
        else
            sudo apt update -qq && sudo apt install -y openjdk-21-jre
        fi
    fi

    # 2. Always set Java 21 as default JVM
    if [ -x /usr/lib/jvm/java-21-openjdk-amd64/bin/java ]; then
        echo "Setting Java 21 as default JVM..."
        sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 2>/dev/null || true
    fi

    # 3. Ensure required network and SSL tools
    local missing_tools=()
    command -v wget &>/dev/null || missing_tools+=(wget)
    command -v curl &>/dev/null || missing_tools+=(curl)
    command -v aria2c &>/dev/null || missing_tools+=(aria2)
    command -v certutil &>/dev/null || missing_tools+=(libnss3-tools)

    if [ ${#missing_tools[@]} -gt 0 ]; then
        if [ "$installer" = "nala" ]; then
            sudo nala install -y "${missing_tools[@]}"
        else
            sudo apt install -y "${missing_tools[@]}"
        fi
    fi
}

distro_sandbox_check() {
    burp_enable_debian_userns
}

run_burp_installation "Kali Linux" distro_install_deps distro_sandbox_check "$@"
