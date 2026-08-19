#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX GAMING STACK INSTALLATION (WINE, LUTRIS, GAMEMODE, DXVK)
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting Gaming Stack installation..."

# List of official repository gaming packages
gaming_packages=(
    alsa-lib alsa-plugins gamemode giflib gnutls gst-plugins-base-libs gtk3 innoextract
    lib32-alsa-lib lib32-alsa-plugins lib32-gamemode lib32-giflib lib32-gnutls
    lib32-gtk3 lib32-libpulse lib32-libva lib32-libxcomposite
    lib32-ocl-icd lib32-sdl2 lib32-sqlite lib32-v4l-utils lib32-vkd3d lib32-vulkan-icd-loader
    libayatana-appindicator libpulse libva libxcomposite ocl-icd python-protobuf sdl2 sqlite
    v4l-utils vkd3d vulkan-icd-loader wine-gecko wine-mono wine-staging winetricks
    umu-launcher python-pefile vulkan-tools lutris
)

# List of gaming-specific AUR packages
gaming_aur_packages=(
    "dxvk-gplasync-bin"
    "lib32-gst-plugins-base-libs"
    "lib32-gstreamer"
)

# 1. Install official repository gaming packages
log "Installing official repository gaming dependencies..."
sudo pacman -S --needed --noconfirm --overwrite '*' "${gaming_packages[@]}"

# 2. Install AUR gaming packages (DXVK async, 32-bit GStreamer)
if command -v paru &>/dev/null; then
    log "Installing AUR gaming extensions (DXVK async, 32-bit GStreamer)..."
    paru -S --needed --noconfirm "${gaming_aur_packages[@]}" || true
elif command -v yay &>/dev/null; then
    log "Installing AUR gaming extensions via yay..."
    yay -S --needed --noconfirm "${gaming_aur_packages[@]}" || true
else
    log "Notice: No AUR helper found. Skipping AUR gaming packages."
fi

# 3. Enable GameMode daemon service if available
if systemctl --user list-unit-files | grep -q "gamemoded.service"; then
    log "Enabling GameMode user daemon..."
    systemctl --user enable --now gamemoded.service 2>/dev/null || true
fi

# 4. Add user to gamemode group if group exists
if getent group gamemode &>/dev/null; then
    sudo usermod -aG gamemode "$USER" 2>/dev/null || true
fi

log "Gaming stack installation and configuration completed successfully!"
