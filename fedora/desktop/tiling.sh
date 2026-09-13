#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA X11 TILING WINDOW MANAGER ENVIRONMENT
# Package mapping of arch/desktop/tiling.sh.
#   i3lock-color         COPR tokariew/i3lock-color (system/repos.sh)
#   nwg-look             no Fedora build -> lxappearance
#   clipmenu             no Fedora build -> copyq
#   JetBrains Mono Nerd  GitHub ryanoasis/nerd-fonts -> ~/.local/share/fonts
#   Dracula GTK          GitHub dracula/gtk -> ~/.themes
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

x11_tiling_packages=(
    xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-drv-libinput xbacklight xdpyinfo
    accountsservice acpi alsa-firmware arandr abattis-cantarell-fonts
    bluez bluez-tools blueman brightnessctl copyq dex-autostart dmenu dmidecode
    dunst feh ffmpegthumbnailer flameshot gammastep
    gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
    haveged hdparm hwinfo kitty logrotate ModemManager mpv-mpris network-manager-applet nitrogen
    numlockx google-noto-sans-fonts google-noto-sans-cjk-fonts google-noto-color-emoji-fonts
    lxappearance os-prober papirus-icon-theme picom playerctl xfce-polkit polybar poppler-glib
    qalculate-qt qbittorrent rofi scrot sysstat Thunar thunar-archive-plugin thunar-volman tumbler
    jetbrains-mono-fonts-all usb_modeswitch wmname xarchiver xbindkeys xclip
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs-gtk xfce4-terminal xss-lock
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps
)

# 1. Repository packages
copr_enable tokariew/i3lock-color
log "Installing X11 tiling packages..."
dnf_install "${x11_tiling_packages[@]}"

# 2. i3lock-color replaces the stock i3lock
if rpm -q i3lock &>/dev/null && ! is_simulate; then
    log "Removing stock i3lock in favor of i3lock-color..."
    $SUDO dnf remove -y i3lock
fi
dnf_install i3lock-color

# 3. JetBrains Mono Nerd Font (Arch: ttf-jetbrains-mono-nerd)
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
if [ -d "$FONT_DIR" ]; then
    log "JetBrains Mono Nerd Font already installed"
else
    url="$(github_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz$')"
    [ -n "$url" ] || die "JetBrains Mono Nerd Font release not found"
    if is_simulate; then
        url_check "$url"
    else
        mkdir -p "$FONT_DIR"
        curl -fSL --retry 3 "$url" | tar -xJ -C "$FONT_DIR"
        fc-cache -f "$FONT_DIR" >/dev/null
        log "Installed JetBrains Mono Nerd Font to $FONT_DIR"
    fi
fi

# 4. Dracula GTK theme (Arch: dracula-gtk-theme)
if [ -d "$HOME/.themes/Dracula" ]; then
    log "Dracula GTK theme already installed"
else
    url="$(github_asset_url dracula/gtk 'Dracula\.tar\.xz$')"
    [ -n "$url" ] || die "Dracula GTK release not found"
    if is_simulate; then
        url_check "$url"
    else
        mkdir -p "$HOME/.themes"
        curl -fSL --retry 3 "$url" | tar -xJ -C "$HOME/.themes"
        log "Installed Dracula GTK theme to ~/.themes"
    fi
fi

# 5. Precision touchpad (libinput)
if [ -f "$SCRIPT_DIR/../hardware/touchpad.sh" ]; then
    log "Configuring X11 precision touchpad (fedora/hardware/touchpad.sh)..."
    bash "$SCRIPT_DIR/../hardware/touchpad.sh" || warn "Touchpad configuration failed"
fi

# 6. Services
enable_service bluetooth.service --now
if ! in_container; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" &>/dev/null; then
            systemctl --user start "$s" 2>/dev/null || true
        fi
    done
fi

# 7. Default applications & user directories
if command -v zathura &>/dev/null; then
    xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
fi
if command -v xdg-user-dirs-update &>/dev/null; then
    xdg-user-dirs-update 2>/dev/null || true
fi

log "X11 tiling window manager configuration complete."
