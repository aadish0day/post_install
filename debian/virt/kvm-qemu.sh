#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KVM / QEMU / virt-manager (Debian/Ubuntu)
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

kvm_packages=(
    qemu-system-x86 qemu-system-gui qemu-utils
    libvirt-daemon-system libvirt-clients virt-manager virt-viewer virtinst
    dnsmasq-base bridge-utils vde2 iptables nftables netcat-openbsd
    libguestfs-tools swtpm swtpm-tools ovmf
)

# qemu-user-static was replaced by qemu-user-binfmt (Ubuntu 25.10+); the two conflict
if apt_available qemu-user-static | grep -qx qemu-user-static; then
    kvm_packages+=(qemu-user-static)
else
    kvm_packages+=(qemu-user-binfmt)
fi

log "Installing KVM and QEMU packages..."
apt_install "${kvm_packages[@]}"

add_user_group kvm
add_user_group libvirt

if is_simulate; then
    log "[simulate] would configure libvirtd and the default network"
    exit 0
fi

conf=/etc/libvirt/libvirtd.conf
if [ -f "$conf" ]; then
    log "Configuring $conf..."
    $SUDO sed -i 's/^#\?\s*unix_sock_group = .*/unix_sock_group = "libvirt"/' "$conf"
    $SUDO sed -i 's/^#\?\s*unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' "$conf"
fi

enable_service libvirtd.service --now

if ! in_container; then
    log "Configuring default virtual network..."
    $SUDO virsh net-start default 2>/dev/null || true
    $SUDO virsh net-autostart default 2>/dev/null || true
fi

log "KVM/QEMU setup complete. Log out and back in for group changes to take effect."
