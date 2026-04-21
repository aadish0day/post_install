#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Installing KDE Plasma Desktop Environment..."

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(
    plasma-desktop sddm
    rsync obsidian elisa gwenview kamoso okular libreoffice-fresh wl-clipboard qt6-tools
    mesa libva-mesa-driver libva-utils vulkan-radeon vulkan-tools dosfstools sshfs kdeconnect
    kclock
)

# Install packages
echo "Installing KDE packages..."
sudo pacman -S --needed --noconfirm "${kde_plasma_packages[@]}"

# Enable SDDM display manager
if pacman -Qi sddm &>/dev/null; then
    if ! systemctl is-enabled sddm.service &>/dev/null; then
        log "Enabling SDDM display manager..."
        sudo systemctl enable sddm.service
    else
        log "SDDM is already enabled."
    fi
fi

log "KDE Plasma installation and configuration complete."
