#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA KVM / QEMU / VIRT-MANAGER
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

kvm_packages=(
    qemu-kvm qemu-img qemu-user-static libvirt libvirt-daemon-kvm libvirt-daemon-config-network
    virt-manager virt-viewer virt-install edk2-ovmf swtpm swtpm-tools dnsmasq guestfs-tools
    bridge-utils nftables
)

log "Installing KVM and QEMU packages..."
dnf_install "${kvm_packages[@]}"

add_user_group kvm libvirt

LIBVIRTD_CONF=/etc/libvirt/libvirtd.conf
if [ -f "$LIBVIRTD_CONF" ]; then
    log "Configuring $LIBVIRTD_CONF..."
    $SUDO sed -i 's/^#\?\s*unix_sock_group = .*/unix_sock_group = "libvirt"/' "$LIBVIRTD_CONF"
    $SUDO sed -i 's/^#\?\s*unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' "$LIBVIRTD_CONF"
fi

if in_container || is_simulate; then
    warn "Skipping libvirt services and default network setup here."
else
    # Fedora uses modular daemons (virtqemud etc.); fall back to monolithic libvirtd
    enable_service virtqemud.socket --now
    enable_service virtnetworkd.socket --now
    systemctl is-enabled virtqemud.socket &>/dev/null || enable_service libvirtd.service --now
    $SUDO virsh net-start default 2>/dev/null || true
    $SUDO virsh net-autostart default 2>/dev/null || true
fi

log "KVM/QEMU setup complete. Log out or reboot for group changes to take effect."
