#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AMD setup script (Arch)
# Installs amd-ucode + P-State kernel tuning when an AMD CPU
# is present, and the Mesa/Vulkan/VA-API stack when an AMD
# (Radeon) GPU is present.
#
# Usage: amd.sh [--pro]
#   --pro  also install AMD Pro AUR packages (AMF, OpenCL, OGLP)
#          via paru/yay; needs an AUR helper and a sudo user.
# ============================================================

# ------------------------- Detection ------------------------
has_amd_cpu() {
    grep -q "AuthenticAMD" /proc/cpuinfo
}

has_amd_gpu() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qiE "\[amd/ati\]|radeon|navi"
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
    echo "AMD CPU detected - installing linux-firmware and amd-ucode..."
    pacman -S --noconfirm --needed linux-firmware amd-ucode
}

tune_grub() {
    local params=("amd_pstate=active" "amd_prefcore=enable")
    local cmdline param

    if [ ! -f /etc/default/grub ]; then
        echo "GRUB not found - skipping amd_pstate kernel parameters."
        return
    fi

    # Append missing params instead of overwriting the existing cmdline
    cmdline="$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/p' /etc/default/grub)"
    for param in "${params[@]}"; do
        [[ " $cmdline " == *" $param "* ]] || cmdline="${cmdline:+$cmdline }$param"
    done

    echo "Setting GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"..."
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg || true
}

# ------------------------- Multilib -------------------------
ensure_multilib() {
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo "Enabling multilib repository in /etc/pacman.conf..."
        sed -i '/\[multilib\]/,/Include/s/^[#;]//' /etc/pacman.conf
        pacman -Sy
    fi
}

# ------------------------- GPU ------------------------------
install_gpu() {
    ensure_multilib
    echo "AMD GPU detected - installing Mesa/Vulkan/VA-API support..."
    pacman -S --noconfirm --needed \
        linux-firmware mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        xf86-video-amdgpu vulkan-mesa-layers lib32-vulkan-mesa-layers \
        mesa-utils lib32-mesa-utils mesa-demos lib32-mesa-demos glu lib32-glu radeontop
}

install_pro() {
    local helper=""
    command -v paru &>/dev/null && helper="paru"
    [ -z "$helper" ] && command -v yay &>/dev/null && helper="yay"

    if [ -z "$helper" ] || [ -z "${SUDO_USER:-}" ]; then
        echo "Skipping AMD Pro packages: needs paru/yay and a non-root sudo user."
        return
    fi

    # AUR helpers refuse to run as root, so build as the invoking user
    echo "Installing AMD Pro AUR packages with $helper..."
    sudo -u "$SUDO_USER" "$helper" -S --needed --noconfirm \
        vulkan-amdgpu-pro lib32-vulkan-amdgpu-pro amdgpu-pro-oglp lib32-amdgpu-pro-oglp \
        amf-amdgpu-pro opencl-headers
}

# ------------------------- Main -----------------------------
require_root "$@"

INSTALL_PRO=false
for arg in "$@"; do
    case "$arg" in
    --pro) INSTALL_PRO=true ;;
    *)
        echo "Unknown option: $arg" >&2
        exit 1
        ;;
    esac
done

found=false
if has_amd_cpu; then
    install_cpu
    tune_grub
    found=true
fi
if has_amd_gpu; then
    install_gpu
    [ "$INSTALL_PRO" = true ] && install_pro
    found=true
fi

if [ "$found" = false ]; then
    echo "No AMD CPU or GPU detected - nothing to do."
    exit 0
fi

echo "AMD setup completed successfully."
