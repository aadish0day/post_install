#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA AMD CPU / GPU
# Microcode + P-State kernel args when an AMD CPU is present; firmware,
# Mesa Vulkan (64/32-bit) and RPM Fusion's full VA-API/VDPAU drivers when an
# AMD GPU is present.
#
# Usage: amd.sh [--pro]   (--pro is Arch-only; ignored here)
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

for arg in "$@"; do
    case "$arg" in
    --pro) warn "--pro (AMD Pro AUR packages) is Arch-only; ignoring on Fedora." ;;
    *) die "Unknown option: $arg" ;;
    esac
done

has_amd_cpu() { grep -q "AuthenticAMD" /proc/cpuinfo; }
has_amd_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qiE "\[amd/ati\]|radeon|navi"; }

command -v lspci &>/dev/null || dnf_install pciutils

found=false
if has_amd_cpu; then
    log "AMD CPU detected - installing microcode and enabling amd_pstate..."
    dnf_install amd-ucode-firmware microcode_ctl linux-firmware
    grub_add_args amd_pstate=active amd_prefcore=enable
    found=true
fi

if has_amd_gpu; then
    log "AMD GPU detected - installing Mesa/Vulkan/VA-API support..."
    rpmfusion_enable
    dnf_install amd-gpu-firmware mesa-dri-drivers mesa-dri-drivers.i686 \
        mesa-vulkan-drivers mesa-vulkan-drivers.i686 vulkan-loader vulkan-loader.i686 \
        vulkan-tools libva-utils radeontop
    # RPM Fusion builds with H.264/H.265 hardware codecs enabled (VA-API + Vulkan video)
    dnf_install --allowerasing mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686 \
        mesa-vulkan-drivers-freeworld mesa-vulkan-drivers-freeworld.i686
    found=true
fi

if [ "$found" = false ]; then
    log "No AMD CPU or GPU detected - nothing to do."
    exit 0
fi

log "AMD setup completed successfully."
