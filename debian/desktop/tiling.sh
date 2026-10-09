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

# JetBrains Mono Nerd Font (Arch: ttf-jetbrains-mono-nerd)
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
if [ -d "$FONT_DIR" ] || fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    log "JetBrains Mono Nerd Font already installed"
else
    log "Installing JetBrains Mono Nerd Font..."
    url="$(github_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz$')" || true
    url="${url:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz}"
    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would extract $url to $FONT_DIR"
    else
        mkdir -p "$FONT_DIR"
        if curl -fSL --retry 3 "$url" | tar -xJ -C "$FONT_DIR"; then
            if command -v fc-cache >/dev/null 2>&1; then
                fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
            fi
            log "Installed JetBrains Mono Nerd Font to $FONT_DIR"
        else
            warn "Failed to download or extract JetBrains Mono Nerd Font"
            rm -rf "$FONT_DIR"
        fi
    fi
fi

# Dracula GTK theme (Arch AUR dracula-gtk-theme): GitHub release into ~/.themes
if [ -d "$HOME/.themes/Dracula" ]; then
    log "Dracula GTK theme already installed"
else
    log "Installing Dracula GTK theme..."
    url="$(github_asset_url dracula/gtk 'Dracula\.tar\.xz$')" || true
    url="${url:-https://github.com/dracula/gtk/releases/latest/download/Dracula.tar.xz}"
    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would extract $url to ~/.themes"
    else
        mkdir -p "$HOME/.themes"
        if curl -fSL --retry 3 "$url" | tar -xJ -C "$HOME/.themes"; then
            log "Installed Dracula GTK theme to ~/.themes"
        else
            warn "Failed to download or extract Dracula GTK theme"
            rm -rf "$HOME/.themes/Dracula"
        fi
    fi
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
        systemctl --user start "$s" 2>/dev/null || true
    done
fi

if ! is_simulate; then
    log "Configuring default applications..."
    command -v zathura >/dev/null 2>&1 && xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
    command -v thorium-browser >/dev/null 2>&1 && xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
    command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update 2>/dev/null || true
fi

log "X11 tiling window manager configuration complete."
