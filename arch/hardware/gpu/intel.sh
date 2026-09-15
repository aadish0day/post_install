#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Intel setup script (Arch)
# Installs intel-ucode when an Intel CPU is present, and the
# Mesa/Vulkan/VA-API stack when an Intel GPU is present.
# ============================================================

# ------------------------- Detection ------------------------
has_intel_cpu() {
    grep -q "GenuineIntel" /proc/cpuinfo
}

has_intel_gpu() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "intel"
}

# ------------------------- Root check -----------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- CPU ------------------------------
install_cpu() {
    echo "Intel CPU detected - installing linux-firmware and intel-ucode..."
    pacman -S --noconfirm --needed linux-firmware intel-ucode
}

# ------------------------- Multilib -------------------------
ensure_multilib() {
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo "Enabling multilib repository in /etc/pacman.conf..."
        sed -i '/\[multilib\]/,/Include/s/^[#;]//' /etc/pacman.conf
        pacman -Syu --noconfirm
    fi
}

# ------------------------- GPU ------------------------------
install_gpu() {
    ensure_multilib
    echo "Intel GPU detected - installing Mesa/Vulkan/VA-API support..."
    pacman -S --noconfirm --needed \
        linux-firmware mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        intel-media-driver mesa-utils
}

# ------------------------- Main -----------------------------
require_root "$@"

found=false
if has_intel_cpu; then
    install_cpu
    found=true
fi
if has_intel_gpu; then
    install_gpu
    found=true
fi

if [ "$found" = false ]; then
    echo "No Intel CPU or GPU detected - nothing to do."
    exit 0
fi

echo "Intel setup completed successfully."
