#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KDE PLASMA DESKTOP ENVIRONMENT (Debian equivalent of arch/desktop/kde.sh)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

kde_plasma_packages=(
    kde-plasma-desktop plasma-desktop plasma-workspace plasma-nm plasma-discover
    plasma-discover-backend-flatpak kwin-x11 kwin-wayland sddm sddm-theme-breeze
    xdg-desktop-portal-kde
    rsync elisa gwenview koko kamoso okular libreoffice wl-clipboard qt6-tools-dev-tools
    mesa-utils libva-utils mesa-vulkan-drivers vulkan-tools dosfstools sshfs kdeconnect kclock
    kimageformat6-plugins qt6-image-formats-plugins
    # KDE specific apps
    dolphin kate konsole ark kdenlive ffmpegthumbs
)

log "Installing KDE Plasma packages and applications..."
apt_install "${kde_plasma_packages[@]}"

# Obsidian is not in Debian: Pacstall, falling back to Flathub
if ! command -v obsidian >/dev/null 2>&1; then
    log "Installing Obsidian..."
    pacstall_install obsidian-deb || flatpak_install md.obsidian.Obsidian
fi

log "Configuring KDE Plasma services..."
enable_service sddm.service

log "KDE Plasma desktop environment configuration complete."
