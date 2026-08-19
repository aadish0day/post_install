#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================================
# KDE PLASMA DESKTOP ENVIRONMENT SETUP
# ============================================================================

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(
    plasma-desktop plasma-meta plasma-workspace plasma-x11-session plasma-login-manager
    plasma-nm plasma-camera kwin-x11
    rsync obsidian elisa gwenview kamoso okular libreoffice-fresh wl-clipboard qt6-tools
    mesa libva-mesa-driver libva-utils vulkan-radeon vulkan-tools dosfstools sshfs kdeconnect
    kclock
    # KDE specific apps
    dolphin kate konsole ark kdenlive ffmpegthumbs
)

# 1. Install KDE Plasma packages from official repositories
echo "Installing KDE Plasma packages and applications..."
sudo pacman -S --needed --noconfirm --overwrite '*' "${kde_plasma_packages[@]}"

# 2. Service Configuration for KDE Plasma
echo "Configuring KDE Plasma services..."


# Enable Display Manager (SDDM) if present
if systemctl list-unit-files | grep -q "sddm.service"; then
    sudo systemctl enable sddm.service 2>/dev/null || true
fi

# Start XDG desktop portal services for KDE Wayland/X11
for s in xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service xdg-desktop-portal-gtk.service; do
    if systemctl --user list-unit-files | grep -q "$s"; then
        systemctl --user start "$s" 2>/dev/null || true
    fi
done


echo "KDE Plasma desktop environment configuration complete."
