#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================================
# X11 TILING WINDOW MANAGER ENVIRONMENT SETUP
# ============================================================================

# List of X11 tiling desktop essentials
x11_tilling_depen=(
    accountsservice acpi alsa-firmware archlinux-xdg-menu arandr awesome-terminal-fonts
    bluez bluez-utils blueman brightnessctl clipmenu dex ding-libs dmidecode dmraid dmenu
    dnssec-anchors dracut dunst feh flameshot fsarchiver gammastep gssproxy gtksourceview3
    haveged hdparm hwdetect hwinfo inetutils jemalloc libgsf libinstpatch liblqr
    libmaxminddb libmbim libopenraw libpipeline libqmi libqrtr-glib libwnck3 libx86emu
    libxres logrotate lsb-release modemmanager netctl network-manager-applet nitrogen ntp
    numlockx nwg-look os-prober perl-xml-writer picom polkit-gnome polybar poppler-glib
    ppp python-annotated-types python-defusedxml python-orjson python-pyaml python-pydantic
    python-pydantic-core python-pyqt5 python-pyqt5-sip python-typing_extensions rofi scrot
    sg3_utils sysstat systemd-resolvconf tcl thunar thunar-archive-plugin thunar-volman
    ttf-opensans usb_modeswitch wmname xarchiver xbindkeys xclip xdg-desktop-portal
    xdg-desktop-portal-gtk xdg-user-dirs-gtk xfce4-terminal xorg-xbacklight xorg-xdpyinfo xss-lock
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps
)

# List of X11-specific AUR packages
x11_aur_packages=(
    "i3lock-color"
    "dracula-gtk-theme"
)

# 1. Install official repository dependencies
echo "Installing X11 tiling dependencies from pacman..."
sudo pacman -S --needed --noconfirm --overwrite '*' "${x11_tilling_depen[@]}"

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

if command -v thorium-browser &>/dev/null; then
    echo "Setting thorium-browser as the default browser..."
    xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
fi

if command -v xdg-user-dirs-update &>/dev/null; then
    xdg-user-dirs-update 2>/dev/null || true
fi

echo "X11 Tiling Window Manager configuration complete."
