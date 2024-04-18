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

# ------------------------------------------------------
# Install Packages
# ------------------------------------------------------
packages=(virt-manager virt-viewer qemu vde2 ebtables iptables-nft nftables dnsmasq bridge-utils ovmf swtpm)
echo "Installing packages..."
sudo pacman -S --needed "${packages[@]}" || {
    echo "Failed to install packages."
    exit 1
}

# ------------------------------------------------------
# Edit libvirtd.conf
# ------------------------------------------------------
echo "Configuring /etc/libvirt/libvirtd.conf..."
sudo sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sudo sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf
echo 'log_filters="3:qemu 1:libvirt"' | sudo tee -a /etc/libvirt/libvirtd.conf > /dev/null
echo 'log_outputs="2:file:/var/log/libvirt/libvirtd.log"' | sudo tee -a /etc/libvirt/libvirtd.conf > /dev/null

# ------------------------------------------------------
# Add user to the group
# ------------------------------------------------------
echo "Adding $(whoami) to kvm and libvirt groups..."
sudo usermod -a -G kvm,libvirt $(whoami) || {
    echo "Failed to add $(whoami) to groups."
    exit 1
}

# ------------------------------------------------------
# Enable services
# ------------------------------------------------------
echo "Enabling and starting libvirtd service..."
sudo systemctl enable libvirtd && sudo systemctl start libvirtd || {
    echo "Failed to enable or start libvirtd."
    exit 1
}

# ------------------------------------------------------
# Edit qemu.conf
# ------------------------------------------------------
echo "Configuring /etc/libvirt/qemu.conf..."
sudo sed -i "s/#user = \"root\"/user = \"$(whoami)\"/" /etc/libvirt/qemu.conf
sudo sed -i "s/#group = \"root\"/group = \"$(whoami)\"/" /etc/libvirt/qemu.conf

# ------------------------------------------------------
# Restart Services
# ------------------------------------------------------
echo "Restarting libvirtd service..."
sudo systemctl restart libvirtd || {
    echo "Failed to restart libvirtd."
    exit 1
}

# ------------------------------------------------------
# Autostart Network
# ------------------------------------------------------
echo "Setting up default network to autostart..."
sudo virsh net-autostart default || {
    echo "Failed to set default network to autostart."
    exit 1
}

echo "Installation and configuration complete! Please restart your system with 'sudo reboot'."

