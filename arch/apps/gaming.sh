#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX GAMING STACK INSTALLATION (WINE, LUTRIS, GAMEMODE, DXVK)
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting Gaming Stack installation..."

# 0. Ensure multilib repository is enabled (required for 32-bit Wine dependencies)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    log "Enabling multilib repository in /etc/pacman.conf..."
    sudo sed -i '/\[multilib\]/,/Include/s/^[#;]//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
fi

# List of official repository gaming packages (including Lutris Wine dependencies)
gaming_packages=(
    alsa-lib alsa-plugins cups gamemode giflib gnutls gst-plugins-base-libs gtk3
    innoextract lib32-alsa-lib lib32-alsa-plugins lib32-gamemode lib32-gnutls
    lib32-gtk3 lib32-libgcrypt lib32-libgpg-error lib32-libjpeg-turbo lib32-libldap
    lib32-libpng lib32-libpulse lib32-libva lib32-libxcomposite lib32-libxinerama
    lib32-ncurses lib32-ocl-icd lib32-sqlite lib32-vkd3d lib32-vulkan-icd-loader
    libayatana-appindicator libgcrypt libgpg-error libjpeg-turbo libldap libpng
    libpulse libva libxcomposite libxinerama libxslt lutris mpg123 ncurses ocl-icd
    openal python-pefile python-protobuf samba sdl2-compat sqlite umu-launcher
    v4l-utils vkd3d vulkan-icd-loader vulkan-tools wine-gecko wine-mono
    wine-staging winetricks
)

# List of gaming-specific AUR packages
gaming_aur_packages=(
    "dxvk-gplasync-bin"
    "lib32-giflib"
    "lib32-gst-plugins-base-libs"
    "lib32-gstreamer"
    "lib32-mpg123"
    "lib32-openal"
    "lib32-sdl2-compat"
    "lib32-v4l-utils"
)

# 1. Install official repository gaming packages
log "Installing official repository gaming dependencies..."
sudo pacman -S --needed --noconfirm --overwrite '*' "${gaming_packages[@]}"

# 2. Install AUR gaming packages (DXVK async, 32-bit GStreamer, 32-bit Wine dependencies)
if command -v paru &>/dev/null; then
    log "Installing AUR gaming extensions and 32-bit Wine libraries via paru..."
    paru -S --needed --noconfirm "${gaming_aur_packages[@]}" || true
elif command -v yay &>/dev/null; then
    log "Installing AUR gaming extensions and 32-bit Wine libraries via yay..."
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
