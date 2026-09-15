#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# NVIDIA setup (Debian/Ubuntu)
# Open kernel module (DKMS) from non-free, userspace drivers, laptop dynamic
# power management and suspend/resume services.
# ============================================================================

# shellcheck source=../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

has_nvidia_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "nvidia"; }
is_laptop() { compgen -G "/sys/class/power_supply/BAT*" >/dev/null; }

command -v lspci >/dev/null 2>&1 || apt_install pciutils

if ! has_nvidia_gpu; then
    log "No NVIDIA GPU detected - nothing to do."
    exit 0
fi

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Enabling i386 architecture for 32-bit graphics/Vulkan libraries..."
    $SUDO dpkg --add-architecture i386
    apt_force_update
fi

log "NVIDIA GPU detected - installing drivers and Vulkan support..."
if is_ubuntu; then
    apt_install ubuntu-drivers-common libvulkan1 libvulkan1:i386 vulkan-tools
    if ! is_simulate && ! in_container; then
        $SUDO ubuntu-drivers install
        # 32-bit GL/Vulkan driver for Wine/Steam (only a Recommends of nvidia-driver-NNN)
        nv_branch="$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'nvidia-driver-[0-9]*' 2>/dev/null |
            awk '$1 == "ii" { print $2 }' | grep -oE '^nvidia-driver-[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -n1 || true)"
        if [ -n "$nv_branch" ]; then
            apt_install "libnvidia-gl-${nv_branch}:i386"
        else
            warn "No nvidia-driver-NNN package installed; skipping 32-bit NVIDIA libraries."
        fi
    fi
else
    kernel_headers="linux-headers-$(dpkg --print-architecture)"
    # nvidia-open-kernel-dkms supports Turing (GTX 16xx / RTX 20xx) and newer
    apt_install "$kernel_headers" dkms nvidia-open-kernel-dkms nvidia-driver firmware-misc-nonfree \
        nvidia-settings nvidia-vulkan-icd nvidia-vulkan-icd:i386 nvidia-driver-libs:i386 libvulkan1 libvulkan1:i386 \
        nvidia-suspend-common libnvidia-encode1 vulkan-tools
fi

if is_laptop && ! is_simulate; then
    log "Laptop detected - enabling NVIDIA runtime D3 power management..."
    echo 'options nvidia "NVreg_DynamicPowerManagement=0x02"' | $SUDO tee /etc/modprobe.d/nvidia-power.conf >/dev/null
fi

for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
    enable_service "$svc"
done

log "NVIDIA setup completed. Reboot to load the new kernel module."
