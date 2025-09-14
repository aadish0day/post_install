
#!/bin/bash
set -e

log() {
    echo "$1"
}

log "Starting RTL8812AU WiFi driver installation for Kali Linux..."

# Update and install required packages
log "Installing required packages..."
sudo apt-get update
sudo apt-get install -y dkms bc mokutil build-essential libelf-dev "linux-headers-$(uname -r)" git

# Clone and install driver
log "Cloning RTL8812AU driver repository..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git clone -b v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
cd rtl8812au

log "Installing driver..."
sudo make dkms_install

log "Cleaning up..."
cd /
rm -rf "$TEMP_DIR"

# Load module
log "Loading driver module..."
sudo modprobe 8812au

log "RTL8812AU driver installation completed!"
log "For monitor mode: sudo airmon-ng check kill && sudo ip link set wlan0 down && sudo iw dev wlan0 set type monitor && sudo ip link set wlan0 up"
