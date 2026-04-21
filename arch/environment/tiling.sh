#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to install AUR packages
install_aur_packages() {
    local pkg
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            if [[ "$pkg" == "i3lock-color" ]] && pacman -Qq "i3lock" &>/dev/null; then
                sudo pacman -Rns --noconfirm "i3lock"
            fi
            paru -S --noconfirm --needed "$pkg" || echo "Failed to install $pkg"
        else
            echo "$pkg is already installed."
        fi
    done
}

log "Installing X11 Tiling Window Manager Environment..."

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

# Install official packages
echo "Installing official X11 tiling packages..."
sudo pacman -S --needed --noconfirm "${x11_tilling_depen[@]}"

# Install AUR packages
if command -v paru &>/dev/null; then
    log "Installing X11-specific AUR packages..."
    install_aur_packages "${x11_aur_packages[@]}"
else
    log "Warning: paru not found. Skipping AUR packages."
fi

# Service Configuration
log "Configuring services for X11 tiling..."
read -rp "Do you want to enable Bluetooth? (y/n): " enable_bluetooth
if [[ $enable_bluetooth =~ ^[Yy]$ ]]; then
    sudo systemctl enable --now bluetooth.service
    log "Bluetooth service enabled."
fi

# Set default applications
log "Configuring default applications..."
if command -v zathura &>/dev/null; then
    log "Setting Zathura as the default PDF viewer..."
    xdg-mime default org.pwmt.zathura.desktop application/pdf
fi

if command -v thorium-browser &>/dev/null; then
    log "Setting thorium-browser as the default browser..."
    xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
fi

log "X11 Tiling environment installation complete."
