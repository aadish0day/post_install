#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA INTEL CPU / GPU
# Microcode when an Intel CPU is present; firmware, Mesa Vulkan and the
# RPM Fusion nonfree intel-media-driver (VA-API) when an Intel GPU is present.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

has_intel_cpu() { grep -q "GenuineIntel" /proc/cpuinfo; }
has_intel_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "intel"; }

command -v lspci &>/dev/null || dnf_install pciutils

found=false
if has_intel_cpu; then
    log "Intel CPU detected - installing microcode..."
    dnf_install microcode_ctl linux-firmware
    found=true
fi

if has_intel_gpu; then
    log "Intel GPU detected - installing Mesa/Vulkan/VA-API support..."
    rpmfusion_enable
    dnf_install intel-gpu-firmware mesa-dri-drivers mesa-dri-drivers.i686 \
        mesa-vulkan-drivers mesa-vulkan-drivers.i686 vulkan-tools libva-utils \
        intel-media-driver libva-intel-media-driver
    found=true
fi

if [ "$found" = false ]; then
    log "No Intel CPU or GPU detected - nothing to do."
    exit 0
fi

log "Intel setup completed successfully."
