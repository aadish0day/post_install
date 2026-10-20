#!/usr/bin/env bash
# Simple WiFi driver installer for Kali Linux
# Check if running as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
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
installed=0

echo "Downloading driver source from morrownr GitHub repository..."
if git clone --depth 1 https://github.com/morrownr/8821au-20210708.git "$TEMP_DIR/8821au" 2>/dev/null; then
    cd "$TEMP_DIR/8821au"
    chmod +x install-driver.sh
    if ./install-driver.sh --no-prompt 2>/dev/null || ./install-driver.sh; then
        echo "Successfully installed morrownr 8821au driver via DKMS."
        installed=1
    fi
fi
cd /
rm -rf "$TEMP_DIR"

if [ "$installed" -eq 0 ]; then
    echo "GitHub install failed or unavailable. Falling back to Kali APT package (realtek-rtl88xxau-dkms)..."
    if $PKG_MANAGER install -y realtek-rtl88xxau-dkms; then
        echo "Successfully installed realtek-rtl88xxau-dkms from Kali repos."
        installed=1
    else
        echo "Error: Failed to install WiFi driver via morrownr source and APT." >&2
        exit 1
    fi
fi

echo "WiFi drivers installed. Reboot to complete."
