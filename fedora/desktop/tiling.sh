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
    xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-drv-libinput xbacklight xdpyinfo
    accountsservice acpi arandr abattis-cantarell-fonts
    bluez bluez-tools blueman brightnessctl copyq dex-autostart dmenu dmidecode
    dunst feh ffmpegthumbnailer flameshot gammastep
    gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
    hdparm hwinfo kitty logrotate ModemManager mpv-mpris network-manager-applet nitrogen
    numlockx google-noto-sans-fonts google-noto-sans-cjk-fonts google-noto-color-emoji-fonts
    lxappearance os-prober papirus-icon-theme picom playerctl xfce-polkit polybar
    rofi scrot Thunar thunar-archive-plugin thunar-volman tumbler
    jetbrains-mono-fonts-all usb_modeswitch wmname xarchiver xbindkeys xclip
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs-gtk xss-lock
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps
)

# 1. Repository packages
copr_enable tokariew/i3lock-color || warn "Could not enable COPR tokariew/i3lock-color"
log "Installing X11 tiling packages..."
dnf_install "${x11_tiling_packages[@]}"

# 2. Screen locker: prefer i3lock-color, fallback to stock i3lock
if dnf repoquery -q i3lock-color 2>/dev/null | grep -q i3lock-color; then
    if rpm -q i3lock &>/dev/null && ! is_simulate; then
        log "Removing stock i3lock in favor of i3lock-color..."
        $SUDO dnf remove -y i3lock
    fi
    dnf_install i3lock-color
else
    warn "i3lock-color not available in enabled repos, falling back to stock i3lock"
    dnf_install i3lock
fi

# 3. JetBrains Mono Nerd Font (Arch: ttf-jetbrains-mono-nerd)
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
if [ -d "$FONT_DIR" ]; then
    log "JetBrains Mono Nerd Font already installed"
else
    url="$(github_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz$')"
    url="${url:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz}"
    [ -n "$url" ] || die "JetBrains Mono Nerd Font release not found"
    if is_simulate; then
        url_check "$url"
    else
        mkdir -p "$FONT_DIR"
        if curl -fSL --retry 3 "$url" | tar -xJ -C "$FONT_DIR"; then
            if command -v fc-cache &>/dev/null; then
                fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
            fi
            log "Installed JetBrains Mono Nerd Font to $FONT_DIR"
        else
            warn "Failed to download or extract JetBrains Mono Nerd Font"
            rm -rf "$FONT_DIR"
        fi
    fi
fi

# 4. Dracula GTK theme (Arch: dracula-gtk-theme)
if [ -d "$HOME/.themes/Dracula" ]; then
    log "Dracula GTK theme already installed"
else
    url="$(github_asset_url dracula/gtk 'Dracula\.tar\.xz$')"
    url="${url:-https://github.com/dracula/gtk/releases/latest/download/Dracula.tar.xz}"
    [ -n "$url" ] || die "Dracula GTK release not found"
    if is_simulate; then
        url_check "$url"
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

# 5. Precision touchpad (libinput)
if ! in_container && [ -f "$SCRIPT_DIR/../hardware/touchpad.sh" ]; then
    log "Configuring X11 precision touchpad (fedora/hardware/touchpad.sh)..."
    bash "$SCRIPT_DIR/../hardware/touchpad.sh" || warn "Touchpad configuration failed"
elif in_container; then
    warn "Container detected, skipping touchpad hardware configuration"
fi

# 6. Services
enable_service bluetooth.service --now
if ! in_container && ! is_simulate; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if command -v systemctl &>/dev/null && systemctl --user list-unit-files "$s" &>/dev/null; then
            systemctl --user start "$s" 2>/dev/null || true
        fi
    done
fi

# 7. Default applications & user directories
if ! is_simulate; then
    if command -v zathura &>/dev/null; then
        xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
    fi
    if command -v thorium-browser &>/dev/null; then
        xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
    fi
    if command -v xdg-user-dirs-update &>/dev/null; then
        xdg-user-dirs-update 2>/dev/null || true
    fi
fi

log "X11 tiling window manager configuration complete."
