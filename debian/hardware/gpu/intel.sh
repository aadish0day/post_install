#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Intel setup (Debian/Ubuntu)
# intel-microcode for Intel CPUs, Mesa Vulkan + VA-API for Intel GPUs.
# ============================================================================

# shellcheck source=../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

has_intel_cpu() { grep -q "GenuineIntel" /proc/cpuinfo; }
has_intel_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "intel"; }

command -v lspci >/dev/null 2>&1 || apt_install pciutils

found=false
if has_intel_cpu; then
    log "Intel CPU detected - installing microcode..."
    apt_install intel-microcode firmware-linux-free
    found=true
fi

if has_intel_gpu; then
    log "Intel GPU detected - installing Mesa/Vulkan/VA-API support..."
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        $SUDO dpkg --add-architecture i386
        apt_force_update
    fi
    apt_install firmware-misc-nonfree firmware-intel-graphics \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 libvulkan1 libvulkan1:i386 vulkan-tools \
        libgl1-mesa-dri libgl1-mesa-dri:i386 intel-media-va-driver-non-free i965-va-driver-shaders \
        vainfo mesa-utils intel-gpu-tools
    found=true
fi

if [ "$found" = false ]; then
    log "No Intel CPU or GPU detected - nothing to do."
    exit 0
fi

log "Intel setup completed successfully."
