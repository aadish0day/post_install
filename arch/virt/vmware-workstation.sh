#!/usr/bin/env bash
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting VMware Workstation setup on Arch Linux..."

# 1. Install prerequisite base & header packages via pacman
log "Installing linux headers and essential build dependencies..."
sudo pacman -S --needed --noconfirm linux-headers base-devel dkms fuse2 gtkmm3 pcsclite libcanberra --overwrite '*'

# 2. Check/Install paru if missing
if ! command -v paru &>/dev/null; then
    log "paru not found. Installing paru..."
    sudo pacman -S --needed --noconfirm base-devel git
    rm -rf /tmp/paru
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
fi

# 3. Install VMware Workstation and related packages from AUR
virt_packages=(
    "vmware-keymaps"
    "ncurses5-compat-libs"
    "vmware-workstation"
    "bridge-utils"
)

log "Installing VMware Workstation AUR packages..."
paru -S --needed --noconfirm "${virt_packages[@]}"

# 4. Enable and start VMware systemd services
log "Enabling and starting VMware services..."

# Enable networking service for NAT / Host-Only / Bridged network interfaces
if systemctl list-unit-files | grep -q "vmware-networks.service"; then
    log "Enabling vmware-networks service..."
    sudo systemctl enable --now vmware-networks.service
fi

# Enable USB arbitrator service for passing USB devices into VMs
if systemctl list-unit-files | grep -q "vmware-usbarbitrator.service"; then
    log "Enabling vmware-usbarbitrator service..."
    sudo systemctl enable --now vmware-usbarbitrator.service
fi

# Load VMware kernel modules
log "Loading VMware kernel modules..."
sudo modprobe -a vmw_vmci vmmon vmnet 2>/dev/null || true

log "VMware Workstation installation and configuration complete!"
