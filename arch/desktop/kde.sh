#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KDE PLASMA DESKTOP ENVIRONMENT SETUP
# ============================================================================

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(
    plasma-meta plasma-camera
    rsync obsidian elisa gwenview kamoso okular libreoffice-fresh wl-clipboard qt6-tools
    mesa libva-utils vulkan-tools dosfstools sshfs kdeconnect
    kclock
    # KDE specific apps
    dolphin kate konsole ark kdenlive ffmpegthumbs koko
)

# 1. Install KDE Plasma packages from official repositories
echo "Installing KDE Plasma packages and applications..."
sudo pacman -S --needed --noconfirm "${kde_plasma_packages[@]}"

# 2. Service Configuration for KDE Plasma
echo "Configuring KDE Plasma services..."

# Enable a display manager. Plasma 6.7+ ships plasma-login-manager (plasmalogin.service);
# older installs use SDDM. Only one may be enabled.
dm_unit=""
for u in plasmalogin.service sddm.service; do
    if systemctl list-unit-files "$u" 2>/dev/null | grep -q "^$u"; then
        dm_unit="$u"
        break
    fi
done
if [ -n "$dm_unit" ]; then
    echo "Enabling display manager: $dm_unit"
    sudo systemctl enable "$dm_unit"
else
    echo "WARN: no Plasma display manager unit found; you will boot to a TTY." >&2
    echo "      Check: systemctl list-unit-files | grep -iE 'login|sddm'" >&2
fi

# Start XDG desktop portal services for KDE Wayland/X11
if systemctl --user show-environment >/dev/null 2>&1; then
    for s in xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" 2>/dev/null | grep -q "$s"; then
            systemctl --user start --no-block "$s" 2>/dev/null || true
        fi
    done
fi

echo "KDE Plasma desktop environment configuration complete."
