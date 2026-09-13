#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NVIDIA setup script (Arch)
# Installs the open NVIDIA kernel module (DKMS), userspace
# drivers, laptop power management and suspend services.
# ============================================================

# ------------------------- Detection ------------------------
has_nvidia_gpu() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "nvidia"
}

is_laptop() {
    compgen -G "/sys/class/power_supply/BAT*" >/dev/null
}

# ------------------------- Root check -----------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- Drivers --------------------------
install_drivers() {
    echo "NVIDIA GPU detected - installing NVIDIA drivers..."
    # nvidia-open-dkms supports Turing (GTX 16xx / RTX 20xx) and newer.
    # Older cards need the legacy nvidia-*xx-dkms packages from the AUR.
    pacman -S --noconfirm --needed \
        linux-firmware linux-headers nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
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
        systemctl enable --now nvidia-powerd.service
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
