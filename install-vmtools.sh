#!/bin/bash

# VMware Tools Installation Script
# Supports Arch, Debian/Ubuntu, and Fedora-based distributions

set -e

echo "================================================"
echo "  VMware Guest Tools Installation Script"
echo "================================================"
echo ""
echo "This script will install open-vm-tools on your system."
echo ""
echo "Select your operating system:"
echo "1) Arch Linux / Manjaro"
echo "2) Debian / Ubuntu / Linux Mint"
echo "3) Fedora / RHEL / CentOS"
echo "4) Auto-detect"
echo ""
read -p "Enter your choice [1-4]: " choice

install_arch() {
    echo ""
    echo "Installing open-vm-tools for Arch Linux..."
    sudo pacman -S --noconfirm open-vm-tools xf86-input-vmmouse gtkmm3
    
    echo "Enabling services..."
    sudo systemctl enable vmtoolsd.service
    sudo systemctl enable vmware-vmblock-fuse.service
    sudo systemctl start vmtoolsd.service
    sudo systemctl start vmware-vmblock-fuse.service
    
    echo "Adding user to vmware group..."
    # sudo usermod -aG vmware $USER
    
    echo ""
    echo "✓ Installation complete for Arch Linux!"
    echo "⚠ Please log out and back in for group changes to take effect."
}

install_debian() {
    echo ""
    echo "Installing open-vm-tools for Debian/Ubuntu..."
    sudo apt update
    sudo apt install -y open-vm-tools open-vm-tools-desktop
    
    echo ""
    echo "✓ Installation complete for Debian/Ubuntu!"
    echo "Services will start automatically."
}

install_fedora() {
    echo ""
    echo "Installing open-vm-tools for Fedora/RHEL..."
    sudo dnf install -y open-vm-tools open-vm-tools-desktop
    
    echo "Enabling services..."
    sudo systemctl enable vmtoolsd.service
    sudo systemctl start vmtoolsd.service
    
    echo ""
    echo "✓ Installation complete for Fedora/RHEL!"
}

auto_detect() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        
        case "$ID" in
            arch|manjaro|endeavouros)
                echo "Detected: Arch-based system ($PRETTY_NAME)"
                install_arch
                ;;
            ubuntu|debian|linuxmint|pop)
                echo "Detected: Debian-based system ($PRETTY_NAME)"
                install_debian
                ;;
            fedora|rhel|centos|rocky|almalinux)
                echo "Detected: Fedora-based system ($PRETTY_NAME)"
                install_fedora
                ;;
            *)
                echo "Error: Could not auto-detect distribution: $PRETTY_NAME"
                echo "Please select manually."
                exit 1
                ;;
        esac
    else
        echo "Error: Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

case $choice in
    1)
        install_arch
        ;;
    2)
        install_debian
        ;;
    3)
        install_fedora
        ;;
    4)
        auto_detect
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "================================================"
echo "Verifying installation..."
systemctl status vmtoolsd.service --no-pager || systemctl status open-vm-tools --no-pager
echo "================================================"
echo ""
echo "Features now available:"
echo "  ✓ Copy/paste between host and guest"
echo "  ✓ Drag and drop files"
echo "  ✓ Shared folders"
echo "  ✓ Auto screen resolution"
echo "  ✓ Seamless mouse integration"
echo ""
echo "For shared folders, configure them in VMware Workstation"
echo "and they will appear at: /mnt/hgfs/"
echo ""
