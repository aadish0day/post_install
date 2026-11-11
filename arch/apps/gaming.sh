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
# shellcheck source=lib/arch-multilib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/arch-multilib.sh"
ensure_multilib

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
sudo pacman -S --needed --noconfirm "${gaming_packages[@]}"

# 2. Extra packages: anything now in official repos goes through pacman; the rest via an AUR helper
repo_extra=()
aur_needed=()
for p in "${gaming_aur_packages[@]}"; do
    if pacman -Si "$p" &>/dev/null; then
        repo_extra+=("$p")
    else
        aur_needed+=("$p")
    fi
done

if [ ${#repo_extra[@]} -gt 0 ]; then
    log "Installing ${#repo_extra[@]} extra packages from official repos..."
    sudo pacman -S --needed --noconfirm "${repo_extra[@]}"
fi

if [ ${#aur_needed[@]} -gt 0 ]; then
    aur_helper=""
    if command -v paru &>/dev/null; then
        aur_helper="paru"
    elif command -v yay &>/dev/null; then
        aur_helper="yay"
    fi
    if [ -z "$aur_helper" ]; then
        log "WARN: no AUR helper found; skipping AUR packages: ${aur_needed[*]}"
    else
        # One at a time so a single failure doesn't drop the whole batch
        for p in "${aur_needed[@]}"; do
            "$aur_helper" -S --needed --noconfirm "$p" || log "WARN: failed to install AUR package $p"
        done
    fi
fi

# 3. GameMode: gamemoded is a *user* service started on demand via D-Bus; nothing to enable system-wide.

# 4. Add user to gamemode group if group exists
if getent group gamemode &>/dev/null; then
    sudo usermod -aG gamemode "$USER" 2>/dev/null || true
fi

log "Gaming stack installation and configuration completed successfully!"
