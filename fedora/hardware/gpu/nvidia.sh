#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA NVIDIA
# RPM Fusion akmod-nvidia (kernel module rebuilt automatically on kernel
# updates), CUDA/NVENC userspace, laptop dynamic power management and
# suspend/resume services.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

has_nvidia_gpu() { lspci 2>/dev/null | grep -Ei "vga|3d controller|display" | grep -qi "nvidia"; }
is_laptop() { compgen -G "/sys/class/power_supply/BAT*" >/dev/null; }

command -v lspci &>/dev/null || dnf_install pciutils

if ! has_nvidia_gpu && ! is_simulate; then
    log "No NVIDIA GPU detected - nothing to do."
    exit 0
fi
has_nvidia_gpu || warn "No NVIDIA GPU detected; resolving packages anyway (SIMULATE=1)."

rpmfusion_enable
log "Installing NVIDIA drivers (akmod-nvidia)..."
dnf_install kernel-devel kernel-headers akmod-nvidia xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-power nvidia-settings vulkan-loader vulkan-loader.i686 \
    xorg-x11-drv-nvidia-libs.i686 libva-nvidia-driver

if in_container || is_simulate; then
    warn "Skipping module build, power management and services here."
    exit 0
fi

if is_laptop; then
    log "Laptop detected - enabling NVIDIA runtime D3 power management..."
    echo 'options nvidia NVreg_DynamicPowerManagement=0x02' |
        $SUDO tee /etc/modprobe.d/nvidia-power-management.conf >/dev/null
fi

for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service nvidia-powerd.service; do
    enable_service "$svc"
done

log "Building the kernel module (this can take a few minutes)..."
$SUDO akmods --force || warn "akmods build failed; it will retry on next boot"

log "NVIDIA setup completed. Reboot to load the new kernel module."
