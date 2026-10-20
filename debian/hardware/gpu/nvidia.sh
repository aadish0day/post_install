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

is_turing_or_newer() {
    local dev_info
    dev_info="$(lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -i "nvidia" || true)"
    [ -n "$dev_info" ] || return 1

    echo "$dev_info" | grep -Eiq \
        "\b(TU1[0-9]{2}|GA1[0-9]{2}|AD1[0-9]{2}|GH[0-9]{3}|GB[0-9]{3})\b|GeForce\s+(RTX\s+(20|30|40|50)[0-9]{2}|GTX\s+16[56]0)|RTX\s+([0-9]{4}|A[0-9]{4})|TITAN\s+RTX|\b(A100|A40|A30|A16|A10|A2|H100|H200|H800|B100|B200|L40S?|L4)\b"
}

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
    kernel_module_pkg="nvidia-driver"
    if is_turing_or_newer; then
        log "NVIDIA Turing or newer architecture detected: selecting open-source kernel module."
        kernel_module_pkg="nvidia-open-kernel-dkms"
    else
        log "Legacy or unidentified NVIDIA GPU detected: falling back to standard proprietary driver."
        kernel_module_pkg="nvidia-driver"
    fi
    apt_install "$kernel_headers" dkms "$kernel_module_pkg" firmware-misc-nonfree \
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
