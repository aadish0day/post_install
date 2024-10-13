#!/usr/bin/env bash
set -euo pipefail

# Define key and repo details
KEY_ID="8F654886F17D497FEFE3DB448B15A6B0E9A3FA35"
REPO_URL="https://arch.asus-linux.org"
REPO_NAME="g14"

# Function to check for root privileges
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges. Please run as root."
        exit 1
    fi
}

# Add G14 key and repository
add_g14_repo() {
    echo "Adding G14 key..."
    pacman-key --recv-keys "$KEY_ID"
    pacman-key --finger "$KEY_ID"
    pacman-key --lsign-key "$KEY_ID"
    pacman-key --finger "$KEY_ID"

    # Verify keyserver configuration if key fetch fails
    if [ ! -f /etc/pacman.d/gnupg/gpg.conf ] || ! grep -q "keyserver" /etc/pacman.d/gnupg/gpg.conf; then
        echo "Configuring keyserver..."
        echo "keyserver hkp://keyserver.ubuntu.com" >>/etc/pacman.d/gnupg/gpg.conf
    fi

    # Add the G14 repository to pacman.conf
    if ! grep -q "\[$REPO_NAME\]" /etc/pacman.conf; then
        echo "Adding G14 repository..."
        echo -e "\n[$REPO_NAME]\nServer = $REPO_URL" >>/etc/pacman.conf
    fi
}

# Install packages
install_packages() {
    echo "Updating system and installing packages..."
    pacman -Syu --noconfirm
    pacman -S --noconfirm asusctl power-profiles-daemon supergfxctl switcheroo-control rog-control-center
}

# Enable services without starting them
enable_services() {
    echo "Enabling power-profiles-daemon..."
    systemctl enable power-profiles-daemon.service

    echo "Enabling supergfxctl and switcheroo-control..."
    systemctl enable supergfxd.service
    systemctl enable switcheroo-control.service
}

# Run functions
require_root
add_g14_repo
install_packages
enable_services

echo "Installation completed successfully. G14 repo added, keys configured, and all necessary packages installed."
