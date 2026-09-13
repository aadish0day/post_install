#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ASUS ROG setup script (Arch)
# Installs and configures asusctl tooling from the official repos.
# CPU/GPU drivers live in the vendor scripts under gpu/:
#   gpu/amd.sh, gpu/nvidia.sh, gpu/intel.sh
#
# Usage: asus.sh [battery_limit]   (default: 85)
# ============================================================

# ------------------------- Configuration --------------------
BATTERY_LIMIT="${1:-85}"

# ------------------------- Detection ------------------------
detect_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | sed -E 's/.*: //'
}

gpu_description() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller" | sed -E 's/^[0-9a-f:.]+\s+//' | sort -u
}

# ------------------------- Root check -----------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- Packages -------------------------
install_packages() {
    echo "Updating system and installing packages..."
    pacman -Suy --noconfirm
    # Pin asusctl tooling to [extra] so a third-party repo carrying
    # the same package names can't shadow the official build.
    pacman -S --noconfirm --needed power-profiles-daemon extra/asusctl extra/rog-control-center
}

# ------------------------- Services -------------------------
enable_services() {
    echo "Enabling power-profiles-daemon..."
    systemctl enable --now power-profiles-daemon.service

    echo "asusd is triggered by a udev rule and does not need to be enabled."
}

# ------------------------- asusctl config -------------------
configure_asusctl() {
    local limit="$1"
    echo "Configuring asusctl settings..."

    # Set battery charge limit
    echo "Setting battery charge limit to ${limit}%..."
    asusctl battery limit "$limit"

    # Enable custom fan curves for all modes.
    # NOTE: asusd races on consecutive writes and drops updates;
    # a short pause between profiles lets each fan-curve persist.
    echo "Enabling custom fan curves..."
    asusctl fan-curve --mod-profile Quiet --enable-fan-curves true
    sleep 1
    asusctl fan-curve --mod-profile Performance --enable-fan-curves true
    sleep 1
    asusctl fan-curve --mod-profile Balanced --enable-fan-curves true

    echo "Asusctl configuration completed."
}

# ------------------------- Summary --------------------------
print_summary() {
    local session_type="$1"
    local krel kmajor kminor

    echo "=========================================="
    echo " Hardware summary"
    echo "  CPU:     $(detect_cpu_model)"
    echo "  GPU(s):"
    gpu_description | sed 's/^/    /'
    echo "  Session: $session_type"
    echo "  Kernel:  $(uname -r)"

    krel="$(uname -r | cut -d- -f1)"
    kmajor="${krel%%.*}"
    kminor="${krel#*.}"
    kminor="${kminor%%.*}"
    if [ "$kmajor" -lt 6 ] || { [ "$kmajor" -eq 6 ] && [ "$kminor" -lt 19 ]; }; then
        echo "  Warning: kernel < 6.19, some ASUS features may need a newer kernel."
    fi
    echo "  Drivers: run gpu/amd.sh, gpu/nvidia.sh or gpu/intel.sh for CPU & GPU setup."
    echo "=========================================="
}

# ------------------------- Main -----------------------------
require_root "$@"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

install_packages
enable_services
configure_asusctl "$BATTERY_LIMIT"
print_summary "$SESSION_TYPE"

echo "Installation completed successfully."
