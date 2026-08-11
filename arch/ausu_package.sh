#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ASUS ROG setup script (Arch)
# Auto-detects CPU vendor (amd/intel), dGPU vendor
# (nvidia/amd/intel) and the display session (wayland/x11)
# before installing drivers and asusctl tooling.
# ============================================================

# ------------------------- Configuration --------------------
AYUSH_KEY_ID="F79100EF8C802DAB81C323BB8EEA5962FE510E19"
DRAGOON_KEY_ID="8F654886F17D497FEFE3DB448B15A6B0E9A3FA35"
REPO_URL="https://pacman.opengamingcollective.org"
REPO_NAME="ogc"
BATTERY_LIMIT=85

# ------------------------- Detection ------------------------
detect_cpu_vendor() {
    grep -q "GenuineIntel" /proc/cpuinfo && echo "intel" || echo "amd"
}

detect_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | sed -E 's/.*: //'
}

detect_gpu_vendor() {
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        echo "nvidia"
    elif lspci 2>/dev/null | grep -qiE "\[amd/at\]|radeon|navi"; then
        echo "amd"
    elif lspci 2>/dev/null | grep -qiE "intel corporation.*vga|\[8086:"; then
        echo "intel"
    else
        echo "other"
    fi
}



gpu_description() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller" | sed -E 's/^[0-9a-f:.]+\s+//' | sort -u
}

# ------------------------- Root check -----------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$0" "$@"
    fi
}

# ------------------------- OGC repo -------------------------
add_ogc_repo() {
    # Ensure the keyserver is configured before fetching keys
    if [ ! -f /etc/pacman.d/gnupg/gpg.conf ] || ! grep -q "keyserver" /etc/pacman.d/gnupg/gpg.conf; then
        echo "Configuring keyserver..."
        echo "keyserver hkp://keyserver.ubuntu.com" >>/etc/pacman.d/gnupg/gpg.conf
    fi

    echo "Adding Ayush key..."
    pacman-key --recv-keys "$AYUSH_KEY_ID"
    pacman-key --lsign-key "$AYUSH_KEY_ID"

    echo "Adding dragoon key..."
    pacman-key --recv-keys "$DRAGOON_KEY_ID"
    pacman-key --lsign-key "$DRAGOON_KEY_ID"
    pacman-key --finger "$DRAGOON_KEY_ID"

    # Add the OGC repository to pacman.conf
    if ! grep -q "\[$REPO_NAME\]" /etc/pacman.conf; then
        echo "Adding OGC repository..."
        echo -e "\n[$REPO_NAME]\nServer = $REPO_URL" >>/etc/pacman.conf
    fi
}

# ------------------------- Firmware/ucode -------------------
install_firmware() {
    local cpu_vendor="$1"
    echo "Installing linux-firmware and ${cpu_vendor}-ucode..."
    pacman -S --noconfirm --needed linux-firmware
    pacman -S --noconfirm --needed "${cpu_vendor}-ucode"
}

# ------------------------- GPU drivers ----------------------
install_gpu_drivers() {
    local gpu_vendor="$1"
    case "$gpu_vendor" in
        nvidia)
            echo "NVIDIA dGPU detected - installing NVIDIA drivers..."
            pacman -S --noconfirm --needed mesa vulkan-radeon vulkan-icd-loader nvidia-utils

            # nvidia-laptop-power-cfg must be built as a non-root user
            if [ -n "${SUDO_USER:-}" ]; then
                sudo -u "$SUDO_USER" bash -c '
                    cd /tmp &&
                    rm -rf nvidia-laptop-power-cfg &&
                    git clone --depth 1 https://gitlab.com/asus-linux/nvidia-laptop-power-cfg.git &&
                    cd nvidia-laptop-power-cfg &&
                    makepkg -sfi --noconfirm
                '
            else
                echo "nvidia-laptop-power-cfg needs to be built as a non-root user:"
                echo "  git clone https://gitlab.com/asus-linux/nvidia-laptop-power-cfg.git"
                echo "  cd nvidia-laptop-power-cfg && makepkg -sfi"
            fi

            for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
                if [ -f "/usr/lib/systemd/system/$svc" ]; then
                    systemctl enable "$svc"
                fi
            done
            if [ -f /usr/lib/systemd/system/nvidia-powerd.service ]; then
                systemctl enable --now nvidia-powerd.service
            fi
            ;;
        amd)
            echo "AMD GPU detected - ensuring Mesa/Vulkan support..."
            pacman -S --noconfirm --needed mesa vulkan-radeon vulkan-icd-loader
            ;;
        intel)
            echo "Intel GPU detected - ensuring Mesa/Vulkan support..."
            pacman -S --noconfirm --needed mesa vulkan-intel vulkan-icd-loader
            ;;
        *)
            echo "GPU vendor unknown - skipping GPU driver setup."
            ;;
    esac
}

# ------------------------- Packages -------------------------
install_packages() {
    echo "Updating system and installing packages..."
    pacman -Suy --noconfirm
    pacman -S --noconfirm asusctl power-profiles-daemon rog-control-center
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
    local cpu_vendor="$1"
    local session_type="$2"
    local krel kmajor kminor

    echo "=========================================="
    echo " Hardware summary"
    echo "  CPU:     $(detect_cpu_model) ($cpu_vendor)"
    echo "  GPU(s):"
    gpu_description | sed 's/^/    /'
    echo "  Session: $session_type"
    echo "  Kernel:  $(uname -r)"

    krel="$(uname -r | cut -d- -f1)"
    kmajor="${krel%%.*}"
    kminor="${krel#*.}"
    kminor="${kminor%%.*}"
    if [ "$kmajor" -gt 6 ] || { [ "$kmajor" -eq 6 ] && [ "$kminor" -ge 19 ]; }; then
        echo "  Note: kernel >= 6.19, stock kernel is fine (no OGC kernel needed)."
    fi
    echo "=========================================="
}

# ------------------------- Main -----------------------------
require_root
CPU_VENDOR="$(detect_cpu_vendor)"
GPU_VENDOR="$(detect_gpu_vendor)"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

add_ogc_repo
install_firmware "$CPU_VENDOR"
install_gpu_drivers "$GPU_VENDOR"
install_packages
enable_services
configure_asusctl "$BATTERY_LIMIT"
print_summary "$CPU_VENDOR" "$SESSION_TYPE"

echo "Installation completed successfully."
