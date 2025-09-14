#!/bin/bash

# Simple WiFi driver installer for Kali Linux

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo ./wifi-driver.sh"
    exit 1
fi

echo "Installing WiFi drivers..."

# Update and install packages
apt update
apt install -y dkms git build-essential bc libelf-dev linux-headers-$(uname -r) iw rfkill


# Create temporary directory and install driver
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git clone https://github.com/morrownr/8821au-20210708.git
cd 8821au-20210708
chmod +x install-driver.sh
./install-driver.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"


echo "WiFi drivers installed. Reboot to complete."