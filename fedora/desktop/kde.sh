#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA KDE PLASMA DESKTOP
# Package mapping of arch/desktop/kde.sh; Obsidian comes from Flathub.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

kde_plasma_packages=(
    plasma-desktop plasma-workspace plasma-workspace-x11 kwin-x11 sddm sddm-kcm
    plasma-nm plasma-pa kscreen powerdevil bluedevil
    rsync elisa-player gwenview koko kamoso okular libreoffice wl-clipboard qt6-qttools
    mesa-dri-drivers libva-utils mesa-vulkan-drivers vulkan-tools dosfstools fuse-sshfs kdeconnectd kclock
    kf6-kimageformats qt6-qtimageformats
    xdg-desktop-portal-kde xdg-desktop-portal-gtk
    # KDE specific apps
    dolphin kate konsole ark kdenlive ffmpegthumbs
)

log "Installing KDE Plasma packages and applications..."
dnf_install "${kde_plasma_packages[@]}"

log "Installing Obsidian (Flathub)..."
flatpak_install md.obsidian.Obsidian

log "Configuring KDE Plasma services..."
if ! in_container; then
    $SUDO systemctl set-default graphical.target
fi
enable_service sddm.service

if ! in_container; then
    for s in xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" &>/dev/null; then
            systemctl --user start "$s" 2>/dev/null || true
        fi
    done
fi

log "KDE Plasma desktop environment configuration complete."
