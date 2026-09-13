#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# AMD setup (Debian/Ubuntu)
# amd64-microcode + amd_pstate kernel args for AMD CPUs, and the Mesa
# Vulkan/VA-API/VDPAU stack (64-bit and i386) for Radeon GPUs.
#
# Usage: amd.sh [--pro]   (--pro is Arch-only and ignored here)
# ============================================================================

# shellcheck source=../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

for arg in "$@"; do
    case "$arg" in
    --pro) warn "AMD Pro packages are only available on Arch; ignoring --pro." ;;
    *) die "Unknown option: $arg" ;;
    esac
done

has_amd_cpu() { grep -q "AuthenticAMD" /proc/cpuinfo; }
has_amd_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qiE "\[amd/ati\]|radeon|navi"; }

command -v lspci >/dev/null 2>&1 || apt_install pciutils

tune_grub() {
    local params=("amd_pstate=active" "amd_prefcore=enable") cmdline param
    if in_container || [ ! -f /etc/default/grub ]; then
        warn "No GRUB config (or running in a container) - skipping amd_pstate kernel parameters."
        return
    fi
    cmdline="$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/p' /etc/default/grub)"
    for param in "${params[@]}"; do
        [[ " $cmdline " == *" $param "* ]] || cmdline="${cmdline:+$cmdline }$param"
    done
    if is_simulate; then
        log "[simulate] would set GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\""
        return
    fi
    log "Setting GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"..."
    $SUDO sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" /etc/default/grub
    $SUDO update-grub || warn "update-grub failed"
}

found=false
if has_amd_cpu; then
    log "AMD CPU detected - installing microcode and firmware..."
    apt_install amd64-microcode firmware-linux-free
    tune_grub
    found=true
fi

if has_amd_gpu; then
    log "AMD GPU detected - installing Mesa/Vulkan/VA-API support..."
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        $SUDO dpkg --add-architecture i386
        apt_force_update
    fi
    apt_install firmware-amd-graphics \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 libvulkan1 libvulkan1:i386 vulkan-tools \
        libgl1-mesa-dri libgl1-mesa-dri:i386 libglx-mesa0 libglx-mesa0:i386 libglu1-mesa \
        mesa-va-drivers mesa-va-drivers:i386 mesa-vdpau-drivers mesa-vdpau-drivers:i386 \
        xserver-xorg-video-amdgpu vainfo mesa-utils radeontop
    found=true
fi

if [ "$found" = false ]; then
    log "No AMD CPU or GPU detected - nothing to do."
    exit 0
fi

log "AMD setup completed successfully."
