#!/usr/bin/env bash

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
