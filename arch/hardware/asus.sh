#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ASUS ROG Zephyrus G14 Setup Script (Arch Linux)
# Tailored specifically for ASUS ROG Zephyrus G14 (GA402RJ / GA402 Series)
# Hardware: AMD Ryzen 7 6800HS + Radeon 680M / Radeon RX 6700S
#
# Configures:
#   - asusctl tooling & rog-control-center from official [extra] repository
#   - power-profiles-daemon for power profile switching
#   - Battery charge limit (default: 85% for battery longevity)
#   - Custom fan curves for Quiet, Balanced, and Performance modes
#   - ROG Nebula Display panel overdrive & boot sound configuration
#   - Aura keyboard backlight settings
#
# Usage: asus.sh [battery_limit]   (default: 85, range: 20-100)
# ============================================================================

# ------------------------- Configuration ------------------------------------
BATTERY_LIMIT="${1:-85}"

# ------------------------- Hardware Detection -------------------------------
dmi_vendor() {
    cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
}

dmi_product() {
    cat /sys/class/dmi/id/product_name 2>/dev/null || true
}

dmi_board() {
    cat /sys/class/dmi/id/board_name 2>/dev/null || true
}

detect_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | sed -E 's/.*: //'
}

gpu_description() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller" | sed -E 's/^[0-9a-f:.]+\s+//' | sort -u
}

is_zephyrus_g14() {
    local prod board
    prod="$(dmi_product)"
    board="$(dmi_board)"
    grep -qiE "GA402|Zephyrus G14" <<<"$prod $board"
}

# ------------------------- Root Check ---------------------------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- Packages -----------------------------------------
install_packages() {
    echo "Updating package databases and installing ASUS ROG Zephyrus tools..."
    pacman -Sy --noconfirm

    # Pinned to official [extra] to avoid third-party repo shadowing
    pacman -S --noconfirm --needed \
        power-profiles-daemon \
        extra/asusctl \
        extra/rog-control-center
}

# ------------------------- Services -----------------------------------------
enable_services() {
    echo "Enabling and starting power-profiles-daemon.service..."
    systemctl enable --now power-profiles-daemon.service

    # asusd is managed by systemd/udev socket activation, start if not active
    if ! systemctl is-active --quiet asusd 2>/dev/null; then
        echo "Starting asusd.service..."
        systemctl start asusd.service 2>/dev/null || true
    fi
}

# ------------------------- Asusctl & ROG Config ----------------------------
configure_asusctl() {
    local limit="${1:-85}"
    echo "Configuring ASUS ROG Zephyrus G14 settings..."

    # Validate and clamp battery limit
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 20 ] || [ "$limit" -gt 100 ]; then
        limit=85
    fi

    # 1. Set battery charge limit (preserves battery life on Zephyrus G14)
    echo "Setting battery charge limit to ${limit}%..."
    if asusctl battery limit "$limit" 2>/dev/null; then
        echo "Battery charge limit set to ${limit}%."
    else
        echo "Warning: Battery limit could not be set via asusctl." >&2
    fi

    # 2. Enable custom fan curves for all profiles
    echo "Configuring fan curves (Quiet, Balanced, Performance)..."
    for profile in Quiet Balanced Performance; do
        if asusctl fan-curve --mod-profile "$profile" --enable-fan-curves true 2>/dev/null; then
            echo "  [OK] Custom fan curves enabled for profile: $profile"
            sleep 1 # Short pause so asusd persists each fan curve without racing
        else
            echo "  [INFO] Fan curve profile $profile: default applied."
        fi
    done

    # 3. ROG Zephyrus G14 Firmware Attributes (asusctl armoury)
    # Enable Panel Overdrive for 3ms response time on ROG Nebula Display
    if asusctl armoury list 2>/dev/null | grep -q "panel_overdrive"; then
        echo "Enabling ROG Nebula Display panel overdrive (fast response time)..."
        asusctl armoury set panel_overdrive 1 2>/dev/null || true
    fi

    # Optional: silence boot startup chime
    if asusctl armoury list 2>/dev/null | grep -q "boot_sound"; then
        echo "Configuring boot startup sound (mute boot chime)..."
        asusctl armoury set boot_sound 0 2>/dev/null || true
    fi

    # 4. Keyboard Backlight (Aura)
    if asusctl aura --help &>/dev/null; then
        echo "Setting keyboard backlight to static mode..."
        asusctl aura effect static -c "FFFFFF" 2>/dev/null || true
    fi

    echo "ASUS ROG Zephyrus G14 configuration completed."
}

# ------------------------- Summary ------------------------------------------
print_summary() {
    local session_type="$1"

    echo "============================================================"
    echo " ASUS ROG Zephyrus G14 Hardware Summary"
    echo "============================================================"
    echo "  Vendor:       $(dmi_vendor)"
    echo "  Product:      $(dmi_product)"
    echo "  Board:        $(dmi_board)"
    echo "  CPU:          $(detect_cpu_model)"
    echo "  GPU(s):"
    gpu_description | sed 's/^/                /'
    echo "  Session:      $session_type"
    echo "  Kernel:       $(uname -r)"

    if command -v asusctl &>/dev/null; then
        local current_limit
        current_limit="$(asusctl battery info 2>/dev/null || true)"
        [ -n "$current_limit" ] && echo "  Battery:      $current_limit"
    fi

    echo "============================================================"
    echo " Next step: Run arch/hardware/gpu/amd.sh for AMD CPU/GPU drivers."
    echo "============================================================"
}

# ------------------------- Main ---------------------------------------------
require_root "$@"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

if ! is_zephyrus_g14; then
    echo "ERROR: This script is exclusively tailored for ASUS ROG Zephyrus G14 (GA402 series)." >&2
    echo "Detected hardware: $(dmi_vendor) $(dmi_product) ($(dmi_board)). Aborting." >&2
    exit 1
fi

install_packages
enable_services
configure_asusctl "$BATTERY_LIMIT"
print_summary "$SESSION_TYPE"

echo "ASUS ROG Zephyrus G14 setup completed successfully."
