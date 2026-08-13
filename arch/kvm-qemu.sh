#!/usr/bin/env bash
set -euo pipefail

# Check if the script is run as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E "$0" "$@"
fi

echo "=========================================="
echo " KVM / QEMU / Virt-Manager Setup"
echo "=========================================="
read -rp "Do you want to start the installation? (y/n): " response
if [[ ! $response =~ ^[yY]$ ]]; then
    echo "Installation aborted by the user."
    exit 0
fi

# Core virtualization and QEMU packages
# qemu-desktop provides full hardware emulation, UI, audio, and display drivers cleanly without package conflicts
kvm_packages=(
    qemu-desktop
    qemu-user-static
    virt-manager
    virt-viewer
    dnsmasq
    vde2
    iptables-nft
    nftables
    openbsd-netcat
    libguestfs
    swtpm
    ovmf
)

echo "Installing KVM and QEMU packages..."
pacman -S --needed --noconfirm "${kvm_packages[@]}" || {
    echo "Failed to install KVM packages."
    exit 1
}

# Determine target non-root user
USER_NAME="${SUDO_USER:-${USER}}"
if [ "$USER_NAME" = "root" ]; then
    USER_NAME="$(logname 2>/dev/null || echo "$USER")"
fi

if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "root" ]; then
    echo "Adding $USER_NAME to kvm and libvirt groups..."
    usermod -aG kvm,libvirt "$USER_NAME"
fi

# Configure /etc/libvirt/libvirtd.conf safely (idempotent)
echo "Configuring /etc/libvirt/libvirtd.conf..."
sed -i 's/^#\?\s*unix_sock_group = .*/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sed -i 's/^#\?\s*unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf

if ! grep -q "^log_filters=" /etc/libvirt/libvirtd.conf; then
    echo 'log_filters="3:qemu 1:libvirt"' >> /etc/libvirt/libvirtd.conf
fi
if ! grep -q "^log_outputs=" /etc/libvirt/libvirtd.conf; then
    echo 'log_outputs="1:file:/var/log/libvirt/libvirtd.log"' >> /etc/libvirt/libvirtd.conf
fi

# Enable and start libvirt services
echo "Enabling and starting libvirtd service..."
systemctl enable --now libvirtd.service 2>/dev/null || systemctl enable --now virtqemud.socket 2>/dev/null || true

# Ensure default libvirt network is active & set to autostart
echo "Configuring default virtual network..."
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

echo ""
echo "=========================================="
echo "Installation and configuration complete!"
echo "Please log out or reboot for group changes to take effect."
echo "=========================================="
