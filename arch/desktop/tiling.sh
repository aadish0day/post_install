#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================================
# X11 TILING WINDOW MANAGER ENVIRONMENT SETUP
# ============================================================================

WM_CHOICE="${1:-both}"

wm_packages=()
case "$WM_CHOICE" in
i3)
    wm_packages+=(i3-wm)
    echo "Configuring X11 Tiling Environment (i3-wm)..."
    ;;
bspwm)
    wm_packages+=(bspwm sxhkd)
    echo "Configuring X11 Tiling Environment (bspwm + sxhkd)..."
    ;;
both | tiling | *)
    wm_packages=(i3-wm bspwm sxhkd)
    echo "Configuring X11 Tiling Environment (i3-wm + bspwm + sxhkd)..."
    ;;
esac

# List of X11 tiling desktop essentials
x11_tiling_packages=(
    "${wm_packages[@]}"
    xorg-server xorg-xinit xorg-xbacklight xorg-xdpyinfo
    polybar picom dunst rofi dmenu clipmenu nitrogen feh flameshot gammastep scrot xss-lock
    xclip xbindkeys arandr dex nwg-look wmname
    kitty thunar thunar-archive-plugin thunar-volman tumbler xarchiver
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps
    acpi alsa-firmware brightnessctl mpv-mpris playerctl
    bluez bluez-utils blueman network-manager-applet modemmanager
    hdparm hwdetect hwinfo dmidecode usb_modeswitch
    accountsservice logrotate lsb-release ntp numlockx os-prober
    polkit-gnome systemd-resolvconf inetutils tcl perl-xml-writer
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs-gtk
    ffmpegthumbnailer gtksourceview3 poppler-glib
    gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
    cantarell-fonts awesome-terminal-fonts papirus-icon-theme
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-opensans
)

# List of X11-specific AUR packages
x11_aur_packages=(
    "i3lock-color"
    "dracula-gtk-theme"
)

# 1. Install official repository dependencies
echo "Installing X11 tiling dependencies from pacman..."
sudo pacman -S --needed --noconfirm --overwrite '*' "${x11_tiling_packages[@]}"

# 2. Handle i3lock conflict and install AUR packages
if pacman -Qq "i3lock" &>/dev/null; then
    echo "Removing standard i3lock in favor of i3lock-color..."
    sudo pacman -Rns --noconfirm "i3lock" || true
fi

if command -v paru &>/dev/null; then
    echo "Installing X11-specific AUR packages (i3lock-color, dracula-gtk-theme)..."
    paru -S --needed --noconfirm "${x11_aur_packages[@]}" || true
fi

# 3. Configure Precision Touchpad for X11 (libinput)
if [ -f "$ARCH_DIR/hardware/touchpad.sh" ]; then
    echo "Configuring X11 Precision Touchpad (arch/hardware/touchpad.sh)..."
    bash "$ARCH_DIR/hardware/touchpad.sh" || true
fi

# 4. Service Configuration for X11 Tiling
echo "Configuring services for X11 tiling..."

# Enable Bluetooth service
if systemctl list-unit-files | grep -q "bluetooth.service"; then
    sudo systemctl enable --now bluetooth.service 2>/dev/null || true
    echo "Bluetooth service enabled."
fi

# Enable DBus broker/daemon user service
if systemctl list-unit-files | grep -q "dbus-broker.service"; then
    systemctl --user enable --now dbus-broker.service 2>/dev/null || true
elif systemctl list-unit-files | grep -q "dbus-daemon.service"; then
    systemctl --user enable --now dbus-daemon.service 2>/dev/null || true
fi

# Start XDG desktop portal services
for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
    if systemctl --user list-unit-files | grep -q "$s"; then
        systemctl --user start "$s" 2>/dev/null || true
    fi
done

# 5. Set default applications & user directories
echo "Configuring default applications..."
if command -v zathura &>/dev/null; then
    echo "Setting Zathura as the default PDF viewer..."
    xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
fi

if command -v thorium-browser-avx2 &>/dev/null; then
    echo "Setting thorium-browser-avx2 as the default browser..."
    xdg-settings set default-web-browser thorium-browser-avx2.desktop 2>/dev/null || true
elif command -v thorium-browser-avx &>/dev/null; then
    echo "Setting thorium-browser-avx as the default browser..."
    xdg-settings set default-web-browser thorium-browser-avx.desktop 2>/dev/null || true
elif command -v thorium-browser-sse4 &>/dev/null; then
    echo "Setting thorium-browser-sse4 as the default browser..."
    xdg-settings set default-web-browser thorium-browser-sse4.desktop 2>/dev/null || true
elif command -v thorium-browser &>/dev/null; then
    echo "Setting thorium-browser as the default browser..."
    xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
fi

if command -v xdg-user-dirs-update &>/dev/null; then
    xdg-user-dirs-update 2>/dev/null || true
fi

echo "X11 Tiling Window Manager configuration complete."
