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
both | tiling)
    wm_packages=(i3-wm bspwm sxhkd)
    echo "Configuring X11 Tiling Environment (i3-wm + bspwm + sxhkd)..."
    ;;
*)
    echo "ERROR: unknown window manager choice '$WM_CHOICE' (use i3, bspwm or both)." >&2
    exit 1
    ;;
esac

# List of X11 tiling desktop essentials
x11_tiling_packages=(
    "${wm_packages[@]}"
    xorg-server xorg-xinit xorg-xbacklight xorg-xdpyinfo xorg-xset
    polybar picom dunst rofi dmenu clipmenu feh azote python-xlib flameshot gammastep scrot xss-lock
    xclip xbindkeys arandr dex nwg-look wmname mesa-utils
    kitty thunar thunar-archive-plugin thunar-volman tumbler xarchiver
    zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps
    acpi alsa-firmware alsa-utils brightnessctl mpv-mpris pavucontrol playerctl
    bluez bluez-utils blueman geoclue network-manager-applet modemmanager
    hdparm hwdetect hwinfo dmidecode usb_modeswitch
    accountsservice logrotate lsb-release numlockx os-prober
    polkit-gnome systemd-resolvconf inetutils tcl perl-xml-writer
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs-gtk
    ffmpegthumbnailer gtksourceview3 poppler-glib
    gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
    cantarell-fonts awesome-terminal-fonts papirus-icon-theme
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-opensans
    ttf-material-icons adobe-source-han-sans-cn-fonts
)

# List of X11-specific AUR packages
x11_aur_packages=(
    "i3lock-color"
    "dracula-gtk-theme"
)

# systemd-resolvconf conflicts with openresolv; skip it when openresolv is installed
if pacman -Qq openresolv &>/dev/null; then
    filtered=()
    for _p in "${x11_tiling_packages[@]}"; do
        [ "$_p" = "systemd-resolvconf" ] || filtered+=("$_p")
    done
    x11_tiling_packages=("${filtered[@]}")
fi

# 1. Install official repository dependencies
echo "Installing X11 tiling dependencies from pacman..."
sudo pacman -S --needed --noconfirm "${x11_tiling_packages[@]}"

# 2. Handle i3lock conflict and install AUR packages
aur_helper=""
if command -v paru &>/dev/null; then
    aur_helper="paru"
elif command -v yay &>/dev/null; then
    aur_helper="yay"
fi

if [ -z "$aur_helper" ]; then
    echo "WARN: no AUR helper (paru/yay) found; skipping: ${x11_aur_packages[*]}" >&2
else
    i3lock_removed=false
    if pacman -Qq i3lock &>/dev/null; then
        echo "Removing standard i3lock in favor of i3lock-color..."
        sudo pacman -Rns --noconfirm i3lock && i3lock_removed=true
    fi
    echo "Installing X11-specific AUR packages (${x11_aur_packages[*]})..."
    "$aur_helper" -S --needed --noconfirm "${x11_aur_packages[@]}" ||
        echo "WARN: some AUR packages failed to install." >&2
    # Never leave the system without a screen locker
    if [ "$i3lock_removed" = true ] && ! pacman -Qq i3lock-color &>/dev/null; then
        echo "i3lock-color build failed; restoring i3lock."
        sudo pacman -S --needed --noconfirm i3lock
    fi
fi

# 3. Configure Precision Touchpad for X11 (libinput)
if [ -f "$ARCH_DIR/hardware/touchpad.sh" ]; then
    echo "Configuring X11 Precision Touchpad (arch/hardware/touchpad.sh)..."
    bash "$ARCH_DIR/hardware/touchpad.sh" || echo "WARN: touchpad configuration failed." >&2
fi

# 4. Service Configuration for X11 Tiling
echo "Configuring services for X11 tiling..."

# Enable Bluetooth service
if systemctl list-unit-files | grep -q "bluetooth.service"; then
    sudo systemctl enable --now bluetooth.service 2>/dev/null || true
    echo "Bluetooth service enabled."
fi

# Start XDG desktop portal services
if systemctl --user show-environment >/dev/null 2>&1; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" 2>/dev/null | grep -q "$s"; then
            systemctl --user start --no-block "$s" 2>/dev/null || true
        fi
    done
fi

# 5. Set default applications & user directories
echo "Configuring default applications..."
if command -v zathura &>/dev/null; then
    echo "Setting Zathura as the default PDF viewer..."
    xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
fi

if command -v xdg-user-dirs-update &>/dev/null; then
    xdg-user-dirs-update 2>/dev/null || true
fi

# 6. Minimal session setup (only creates files that do not exist)
if [ ! -f "$HOME/.xinitrc" ]; then
    default_wm="i3"
    [ "$WM_CHOICE" = "bspwm" ] && default_wm="bspwm"
    echo "Creating ~/.xinitrc (default WM: $default_wm; override with WM=bspwm startx)..."
    cat >"$HOME/.xinitrc" <<EOF
#!/bin/sh
exec "\${WM:-$default_wm}"
EOF
    chmod +x "$HOME/.xinitrc"
fi
if command -v bspwm &>/dev/null; then
    mkdir -p "$HOME/.config/bspwm" "$HOME/.config/sxhkd"
    if [ ! -f "$HOME/.config/bspwm/bspwmrc" ]; then
        cat >"$HOME/.config/bspwm/bspwmrc" <<'EOF'
#!/bin/sh
pgrep -x sxhkd >/dev/null || sxhkd &
bspc monitor -d 1 2 3 4 5
bspc config border_width 2
bspc config window_gap 8
EOF
        chmod +x "$HOME/.config/bspwm/bspwmrc"
    fi
    if [ ! -f "$HOME/.config/sxhkd/sxhkdrc" ]; then
        cat >"$HOME/.config/sxhkd/sxhkdrc" <<'EOF'
super + Return
	kitty
super + d
	rofi -show drun
super + alt + {q,r}
	bspc {quit,wm -r}
super + {_,shift + }w
	bspc node -{c,k}
super + {1-5}
	bspc desktop -f '^{1-5}'
EOF
    fi
fi
echo "No display manager is installed: log in on a TTY and run 'startx'."

echo "X11 Tiling Window Manager configuration complete."
