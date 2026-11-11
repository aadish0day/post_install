#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NVIDIA setup script (Arch)
# Installs the open NVIDIA kernel module (DKMS), userspace
# drivers, laptop power management and suspend services.
# ============================================================

# ------------------------- Detection ------------------------
# Capture lspci once: piping into `grep -q` under pipefail can SIGPIPE and misreport.
gpu_lines() {
    local out
    out="$(lspci 2>/dev/null || true)"
    grep -Ei "vga|3d controller|display" <<<"$out" || true
}

has_nvidia_gpu() {
    grep -qi "nvidia" <<<"$(gpu_lines)"
}

is_laptop() {
    compgen -G "/sys/class/power_supply/BAT*" >/dev/null
}

# shellcheck source=lib/arch-multilib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/arch-multilib.sh"

# ------------------------- Root check -----------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- Drivers --------------------------
install_drivers() {
    ensure_multilib
    echo "NVIDIA GPU detected - installing NVIDIA drivers..."
    # Manjaro: mhwd matches the driver to its own kernels (linuxXY, not linux)
    if command -v mhwd &>/dev/null; then
        mhwd -a pci nonfree 0300
        pacman -S --noconfirm --needed \
            lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader
        return
    fi
    # nvidia-open-dkms supports Turing (GTX 16xx / RTX 20xx) and newer.
    # Older cards or non-open kernel setups can use nvidia-dkms.
    local dkms_pkg="nvidia-open-dkms"
    if ! pacman -Si "$dkms_pkg" &>/dev/null; then
        dkms_pkg="nvidia-dkms"
    fi
    local kheaders="linux-headers"
    case "$(uname -r 2>/dev/null)" in
    *-lts*) kheaders="linux-lts-headers" ;;
    *-zen*) kheaders="linux-zen-headers" ;;
    *-hardened*) kheaders="linux-hardened-headers" ;;
    esac
    pacman -S --noconfirm --needed \
        linux-firmware "$kheaders" "$dkms_pkg" nvidia-utils lib32-nvidia-utils \
        nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader
}

# ------------------------- Laptop power ---------------------
install_laptop_power_cfg() {
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
}

# ------------------------- Services -------------------------
enable_services() {
    local svc
    for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        if [ -f "/usr/lib/systemd/system/$svc" ]; then
            systemctl enable "$svc"
        fi
    done
    if [ -f /usr/lib/systemd/system/nvidia-powerd.service ]; then
        systemctl enable --now nvidia-powerd.service 2>/dev/null || true
    fi
}

# ------------------------- Main -----------------------------
require_root "$@"

if ! has_nvidia_gpu; then
    echo "No NVIDIA GPU detected - nothing to do."
    exit 0
fi

install_drivers
if is_laptop; then
    install_laptop_power_cfg
fi
enable_services

echo "NVIDIA setup completed successfully. Reboot to load the new kernel module."
