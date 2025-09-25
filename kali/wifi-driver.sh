#!/usr/bin/env bash
# Simple WiFi driver installer for Kali Linux
# Check if running as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E "$0" "$@"
fi

echo "Installing WiFi drivers..."

# Check if nala is available, otherwise use apt
if command -v nala >/dev/null 2>&1; then
    echo "Using nala package manager..."
    PKG_MANAGER="nala"
else
    echo "Nala not found, using apt..."
    PKG_MANAGER="apt"
fi

# Update and install packages
apt update -y
$PKG_MANAGER upgrade -y
$PKG_MANAGER install -y dkms git build-essential bc libelf-dev linux-headers-$(uname -r) iw rfkill

# Create temporary directory and install driver
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading driver source..."
git clone https://github.com/morrownr/8821au-20210708.git
cd 8821au-20210708

echo "Installing driver..."
chmod +x install-driver.sh
./install-driver.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "WiFi drivers installed. Reboot to complete."
