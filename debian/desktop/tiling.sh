#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# X11 TILING WINDOW MANAGER ENVIRONMENT (Debian equivalent of arch/desktop/tiling.sh)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBIAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DEBIAN_DIR/lib/common.sh"

WM_CHOICE="${1:-both}"

wm_packages=()
case "$WM_CHOICE" in
i3)
    wm_packages+=(i3)
    log "Configuring X11 Tiling Environment (i3)..."
    ;;
bspwm)
    wm_packages+=(bspwm sxhkd)
    log "Configuring X11 Tiling Environment (bspwm + sxhkd)..."
    ;;
both | tiling | *)
    wm_packages=(i3 bspwm sxhkd)
    log "Configuring X11 Tiling Environment (i3 + bspwm + sxhkd)..."
    ;;
esac

x11_tiling_packages=(
    "${wm_packages[@]}"
    accountsservice acpi arandr bluez blueman brightnessctl copyq dex dmidecode dunst feh
    ffmpegthumbnailer flameshot gammastep gvfs gvfs-backends hdparm hwinfo
    kitty logrotate lsb-release modemmanager mpv-mpris network-manager network-manager-gnome nitrogen
    numlockx fonts-noto fonts-noto-cjk fonts-noto-color-emoji fonts-noto-extra fonts-open-sans
    fonts-cantarell fonts-jetbrains-mono nwg-look os-prober papirus-icon-theme picom playerctl mate-polkit
    polybar rofi scrot suckless-tools thunar thunar-archive-plugin thunar-volman
    tumbler usb-modeswitch xarchiver xbindkeys xclip xdg-desktop-portal
    xdg-desktop-portal-gtk xdg-user-dirs-gtk xbacklight x11-utils xss-lock
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps xserver-xorg xinit
)

log "Installing X11 tiling dependencies..."
apt_install "${x11_tiling_packages[@]}"

# i3lock-color (Arch AUR): Pacstall builds it; fallback to standard i3lock
if pacstall_installed i3lock-color; then
    log "i3lock-color is already installed."
else
    if pkg_installed i3lock && ! is_simulate; then
        log "Removing standard i3lock in favor of i3lock-color..."
        apt_remove i3lock || true
    fi
    log "Installing i3lock-color..."
    if ! pacstall_install i3lock-color; then
        warn "i3lock-color could not be installed, falling back to standard i3lock..."
        apt_install i3lock || warn "Standard i3lock could not be installed."
    fi
fi

# Desktop theme, icons, cursors, and fonts
if [ -f "$SCRIPT_DIR/theme.sh" ]; then
    bash "$SCRIPT_DIR/theme.sh"
fi

# Precision touchpad for X11 (libinput)
if ! in_container && [ -f "$DEBIAN_DIR/hardware/touchpad.sh" ]; then
    log "Configuring X11 precision touchpad..."
    bash "$DEBIAN_DIR/hardware/touchpad.sh" || warn "Touchpad configuration failed."
elif in_container; then
    warn "Container detected, skipping touchpad hardware configuration"
fi

log "Configuring services for X11 tiling..."
enable_service bluetooth.service --now

if ! in_container && ! is_simulate && systemctl --user show-environment >/dev/null 2>&1; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" 2>/dev/null | grep -q "$s"; then
            systemctl --user start --no-block "$s" 2>/dev/null || true
        fi
    done
fi

if ! is_simulate; then
    log "Configuring default applications..."
    command -v zathura >/dev/null 2>&1 && xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
    command -v thorium-browser >/dev/null 2>&1 && xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
    command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update 2>/dev/null || true
fi

log "X11 tiling window manager configuration complete."
