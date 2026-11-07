#!/usr/bin/env bash
# ============================================================================
# Arch Linux Burp Suite Professional Installer Wrapper
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source common Burp definitions
if [[ -f "$ROOT_DIR/lib/burp-common.sh" ]]; then
    # shellcheck source=lib/burp-common.sh
    source "$ROOT_DIR/lib/burp-common.sh"
fi

# Source shared Burp installer
# shellcheck source=lib/burp-install.sh
source "$ROOT_DIR/lib/burp-install.sh"

# Safe pacman package installer with stale-database recovery and partial-upgrade protection
pacman_install_safe() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 0

    local sudo_cmd=()
    if [[ $EUID -ne 0 ]]; then
        sudo_cmd=(sudo)
    fi

    # Check pacman sync database freshness
    local sync_db="/var/lib/pacman/sync/core.db"
    local db_stale=false
    if [[ ! -f "$sync_db" ]]; then
        db_stale=true
    else
        local db_age
        db_age=$(( $(date +%s) - $(stat -c %Y "$sync_db" 2>/dev/null || echo 0) ))
        # If older than 7 days (604800s) on Arch rolling release, mirrors likely pruned packages
        if (( db_age > 604800 )); then
            db_stale=true
        fi
    fi

    # If database is fresh, try installing without -Sy first to avoid partial upgrades
    if [[ "$db_stale" == false ]]; then
        local err_output
        set +e
        err_output=$("${sudo_cmd[@]}" pacman -S --noconfirm --needed "${pkgs[@]}" 2>&1)
        local rc=$?
        set -e
        if [ $rc -eq 0 ]; then
            return 0
        fi

        echo "$err_output" >&2
        if echo "$err_output" | grep -qiE "404|not found|failed retrieving file|error: failed to commit transaction"; then
            echo "Package download failed (stale mirror cache or 404 detected). Updating pacman databases and retrying..."
        else
            echo "Pacman installation failed. Synchronizing database and retrying..."
        fi
    else
        echo "Pacman sync database is older than 7 days or missing. Synchronizing databases (-Sy)..."
    fi

    # Synchronize and install
    "${sudo_cmd[@]}" pacman -Sy --noconfirm --needed "${pkgs[@]}"
    echo "Note: If you encounter library mismatch issues after installing packages, run 'sudo pacman -Syu' to complete a full system upgrade."
}

distro_install_deps() {
    echo "Configuring dependencies and Java 21 for Burp Suite (Arch Linux)..."

    local missing_pkgs=()

    # 1. Ensure Java 21 runtime is installed
    # Prefer lightweight jre21-openjdk (~150MB) over bulky jdk21-openjdk (~500MB).
    # If JDK 21 or JRE 21 is already present, accept it without reinstalling.
    if pacman -Qi jre21-openjdk &>/dev/null || pacman -Qi jdk21-openjdk &>/dev/null || [ -x /usr/lib/jvm/java-21-openjdk/bin/java ]; then
        echo "Java 21 environment already present."
    else
        echo "Java 21 not found. Selecting jre21-openjdk (lightweight runtime)..."
        missing_pkgs+=(jre21-openjdk)
    fi

    # Note: We deliberately do NOT change the system-wide default JVM using archlinux-java.
    # The Burp launcher directly specifies Java 21 binary, so altering the system default
    # is unneeded and would break other tools requiring different JVM versions.

    # 2. Check required network, SSL, and desktop integration tools
    local tool
    for tool in wget curl aria2c openssl certutil rsvg-convert update-desktop-database update-mime-database notify-send ss unshare gtk-update-icon-cache xdotool; do
        if ! command -v "$tool" &>/dev/null; then
            case "$tool" in
            aria2c) missing_pkgs+=(aria2) ;;
            certutil) missing_pkgs+=(nss) ;;
            rsvg-convert) missing_pkgs+=(librsvg) ;;
            update-desktop-database) missing_pkgs+=(desktop-file-utils) ;;
            update-mime-database) missing_pkgs+=(shared-mime-info) ;;
            notify-send) missing_pkgs+=(libnotify) ;;
            ss) missing_pkgs+=(iproute2) ;;
            unshare) missing_pkgs+=(util-linux) ;;
            gtk-update-icon-cache) missing_pkgs+=(gtk-update-icon-cache) ;;
            *) missing_pkgs+=("$tool") ;;
            esac
        fi
    done

    # Ensure python is available for JSON configuration and policies parsing
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        missing_pkgs+=(python)
    fi

    # 3. Ensure xorg-xwayland is present for Wayland / KDE Wayland sessions
    # (Burp runs via AWT X11 toolkit over XWayland; missing xorg-xwayland causes launch failure)
    if ! pacman -Qi xorg-xwayland &>/dev/null; then
        missing_pkgs+=(xorg-xwayland)
    fi

    # 4. Ensure CA certificates packages
    if ! pacman -Qi ca-certificates &>/dev/null; then
        missing_pkgs+=(ca-certificates)
    fi
    if ! pacman -Qi ca-certificates-utils &>/dev/null; then
        missing_pkgs+=(ca-certificates-utils)
    fi

    # Deduplicate missing packages
    local -a unique_pkgs=()
    local p
    for p in "${missing_pkgs[@]}"; do
        local seen=false
        local u
        for u in "${unique_pkgs[@]}"; do
            if [[ "$u" == "$p" ]]; then
                seen=true
                break
            fi
        done
        if [[ "$seen" == false ]]; then
            unique_pkgs+=("$p")
        fi
    done
    missing_pkgs=("${unique_pkgs[@]}")

    # 5. Install any missing packages safely
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        pacman_install_safe "${missing_pkgs[@]}"
    else
        echo "All dependencies and tools are already satisfied."
    fi
}

distro_sandbox_check() {
    burp_check_user_namespaces
}

run_burp_installation "Arch Linux" distro_install_deps distro_sandbox_check "$@"
