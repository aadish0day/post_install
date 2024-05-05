#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
	echo "This script must be run as root. Please use sudo."
	exit 1
fi

echo "START KVM/QEMU/VIRT MANAGER INSTALLATION..."
read -p "Do you want to start the installation? (yes/no) " response
if [[ ! $response =~ ^[Yy][Ee][Ss]$ ]]; then
	echo "Installation aborted by the user."
	exit 0
fi

# Install Packages
packages=(virt-manager virt-viewer qemu vde2 ebtables dnsmasq bridge-utils ovmf swtpm iptables-nft nftables)
echo "Installing packages..."
pacman -S --needed "${packages[@]}" || {
	echo "Failed to install packages."
	exit 1
}

# Edit libvirtd.conf
echo "Configuring /etc/libvirt/libvirtd.conf..."
sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf
echo 'log_filters="3:qemu 1:libvirt"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null
echo 'log_outputs="2:file:/var/log/libvirt/libvirtd.log"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null

# Add user to the group
echo "Adding $(whoami) to kvm and libvirt groups..."
usermod -a -G kvm,libvirt $(whoami) || {
	echo "Failed to add $(whoami) to groups."
	exit 1
}

# Enable and start services
echo "Enabling and starting libvirtd service..."
systemctl enable --now libvirtd || {
	echo "Failed to enable or start libvirtd."
	exit 1
}

# Restart libvirtd service after all configurations
echo "Restarting libvirtd service..."
systemctl restart libvirtd || {
	echo "Failed to restart libvirtd."
	exit 1
}

# Set default network to autostart
echo "Setting up default network to autostart..."
virsh net-autostart default || {
	echo "Failed to set default network to autostart."
	exit 1
}

echo "Installation and configuration complete! Please restart your system with 'sudo reboot'."
