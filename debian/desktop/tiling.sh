#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# X11 TILING WINDOW MANAGER ENVIRONMENT (Debian equivalent of arch/desktop/tiling.sh)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBIAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DEBIAN_DIR/lib/common.sh"

x11_tiling_packages=(
    accountsservice acpi arandr bluez blueman brightnessctl dex dmidecode dunst feh
    ffmpegthumbnailer flameshot fsarchiver gammastep gvfs gvfs-backends haveged hdparm hwinfo
    kitty libgsf-bin logrotate lsb-release modemmanager mpv-mpris network-manager network-manager-gnome
    nitrogen numlockx fonts-noto fonts-noto-cjk fonts-noto-color-emoji fonts-noto-extra fonts-open-sans
    fonts-cantarell fonts-jetbrains-mono nwg-look os-prober papirus-icon-theme picom playerctl mate-polkit
    polybar ppp qalculate-gtk qbittorrent rofi scrot sysstat thunar thunar-archive-plugin thunar-volman
    tumbler usb-modeswitch suckless-tools xarchiver xbindkeys xclip xdg-desktop-portal
    xdg-desktop-portal-gtk xdg-user-dirs-gtk xfce4-terminal xbacklight x11-utils xss-lock
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps xserver-xorg xinit
    clipit
)

log "Installing X11 tiling dependencies..."
apt_install "${x11_tiling_packages[@]}"

# i3lock-color (Arch AUR): Pacstall builds it; conflicts with plain i3lock
if pkg_installed i3lock && ! is_simulate; then
    log "Removing standard i3lock in favor of i3lock-color..."
    $SUDO apt-get remove -y i3lock || true
fi
log "Installing i3lock-color..."
pacstall_install i3lock-color || warn "i3lock-color could not be installed."

# JetBrains Mono Nerd Font: Pacstall, falling back to the GitHub release
install_nerd_font_github() {
    local url dest="$HOME/.local/share/fonts/JetBrainsMonoNerd"
    url="$(github_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz$')" || return 1
    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would extract $url to $dest"
        return 0
    fi
    mkdir -p "$dest"
    curl -fL "$url" | tar -xJ -C "$dest"
    fc-cache -f "$dest" >/dev/null 2>&1 || true
}
log "Installing JetBrains Mono Nerd Font..."
if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    pacstall_install ttf-jetbrains-mono-nerd || install_nerd_font_github || warn "Nerd font installation failed."
fi

# Dracula GTK theme (Arch AUR dracula-gtk-theme): GitHub release into ~/.themes
log "Installing Dracula GTK theme..."
if [ ! -d "$HOME/.themes/Dracula" ]; then
    url="$(github_asset_url dracula/gtk 'Dracula\.tar\.xz$')" || true
    if [ -z "${url:-}" ]; then
        warn "Could not resolve Dracula GTK release."
    elif is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would extract $url to ~/.themes"
    else
        mkdir -p "$HOME/.themes"
        curl -fL "$url" | tar -xJ -C "$HOME/.themes"
    fi
fi

# Precision touchpad for X11 (libinput)
if [ -f "$DEBIAN_DIR/hardware/touchpad.sh" ]; then
    log "Configuring X11 precision touchpad..."
    bash "$DEBIAN_DIR/hardware/touchpad.sh" || warn "Touchpad configuration failed."
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
