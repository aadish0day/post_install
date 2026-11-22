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
    # Bug fix: dpkg -l exits 0 even for unknown/removed packages; use dpkg -s instead
    local java_21_installed=false
    if dpkg -s openjdk-21-jre &>/dev/null || dpkg -s openjdk-21-jdk &>/dev/null; then
        java_21_installed=true
    fi
    # Also accept any installed JVM path (amd64 or arm64)
    local java_21_path=""
    for _j in /usr/lib/jvm/java-21-openjdk-amd64/bin/java \
               /usr/lib/jvm/java-21-openjdk-arm64/bin/java \
               /usr/lib/jvm/java-21-openjdk/bin/java; do
        if [ -x "$_j" ]; then
            java_21_path="$_j"
            java_21_installed=true
            break
        fi
    done

    if [ "$java_21_installed" = false ]; then
        echo "Installing OpenJDK 21..."
        if [ "$installer" = "nala" ]; then
            sudo nala install -y openjdk-21-jre
        else
            sudo apt-get update -qq && sudo apt-get install -y openjdk-21-jre
        fi
        # Re-detect path after install
        for _j in /usr/lib/jvm/java-21-openjdk-amd64/bin/java \
                   /usr/lib/jvm/java-21-openjdk-arm64/bin/java \
                   /usr/lib/jvm/java-21-openjdk/bin/java; do
            if [ -x "$_j" ]; then
                java_21_path="$_j"
                break
            fi
        done
    fi

    # 2. Make Java 21 the default JVM only if the current default is older (or missing).
    #    A newer default is left alone; this changes the system-wide JVM for every Java tool.
    if [ -n "$java_21_path" ]; then
        local cur_major
        cur_major="$(java -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p' || true)"
        if [ -z "$cur_major" ] || [ "$cur_major" -lt 21 ]; then
            echo "Setting Java 21 as default JVM ($java_21_path) (current default: ${cur_major:-none})..."
            sudo update-alternatives --set java "$java_21_path" 2>/dev/null || true
        else
            echo "Default JVM is Java $cur_major (>= 21); leaving system default unchanged."
        fi
    fi

    # 3. Ensure required network, SSL, and desktop integration tools
    local missing_tools=()
    command -v wget &>/dev/null || missing_tools+=(wget)
    command -v curl &>/dev/null || missing_tools+=(curl)
    command -v aria2c &>/dev/null || missing_tools+=(aria2)
    command -v certutil &>/dev/null || missing_tools+=(libnss3-tools)
    command -v rsvg-convert &>/dev/null || missing_tools+=(librsvg2-bin)
    command -v update-desktop-database &>/dev/null || missing_tools+=(desktop-file-utils)

    if [ ${#missing_tools[@]} -gt 0 ]; then
        if [ "$installer" = "nala" ]; then
            sudo nala install -y "${missing_tools[@]}"
        else
            # Bug fix: apt-get update required before installing packages with plain apt
            sudo apt-get update -qq && sudo apt-get install -y "${missing_tools[@]}"
        fi
    fi
}

distro_sandbox_check() {
    burp_enable_debian_userns
}

run_burp_installation "Kali Linux" distro_install_deps distro_sandbox_check "$@"
