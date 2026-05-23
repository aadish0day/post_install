#!/usr/bin/env bash

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(
    plasma-desktop plasma-meta
    rsync obsidian elisa gwenview kamoso okular libreoffice-fresh wl-clipboard qt6-tools
    mesa libva-mesa-driver libva-utils vulkan-radeon vulkan-tools dosfstools sshfs kdeconnect
    kclock plasma-meta 
)

# Start xdg-desktop-portal service
systemctl --user start xdg-desktop-portal.service
systemctl --user start plasma-xdg-desktop-portal-kde.service
