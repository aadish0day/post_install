#!/usr/bin/env bash
set -euo pipefail

# Update system and packages
sudo pacman -Sy --noconfirm
# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm

# Prompt user to configure mirrors
read -p "Do you want to configure the mirror list for India using reflector? (y/n): " configure_mirrors
if [[ $configure_mirrors =~ ^[Yy]$ ]]; then
    sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist
else
    echo "Skipping mirror configuration."
fi

# Update system and packages after mirror update
sudo pacman -Syu --noconfirm

# Function to install packages if not already installed
install_if_needed() {
    local pkg
    local failures=()
    local to_install=()
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
        if ! sudo pacman -S --noconfirm "${to_install[@]}"; then
            echo "Some packages failed to install, checking..."
            for pkg in "${to_install[@]}"; do
                if ! pacman -Qi "$pkg" &>/dev/null; then
                    echo "Failed to install $pkg"
                    failures+=("$pkg")
                fi
            done
            if [ ${#failures[@]} -gt 0 ]; then
                echo "Failed to install the following packages: ${failures[*]}"
                return 1
            fi
        fi
    fi
}

# List of general packages to install
packages=(
    neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman bat alacritty zsh jpegoptim zip unrar tar p7zip zstd lz4 xz trash-cli lxrandr mkinitcpio ttf-fira-mono papirus-icon-theme tree otf-firamono-nerd zoxide xdg-desktop-portal xdg-desktop-portal-gtk zed autotiling ueberzugpp qutebrowser ttf-hack-nerd lsd noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
)

# List of gaming packages to install
gaming_packages=(
    lutris wine wine-gecko wine-mono winetricks gamemode lib32-gamemode giflib lib32-giflib gnutls lib32-gnutls v4l-utils lib32-v4l-utils libpulse lib32-libpulse alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader sdl2 lib32-sdl2 innoextract libayatana-appindicator lib32-vkd3d python-protobuf vkd3d
)

# List of i3wm-specific packages
i3wm_packages=(
    acpi arandr archlinux-xdg-menu awesome-terminal-fonts dex dmenu dunst feh galculator gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb i3-wm i3blocks i3status jq nwg-look mpv network-manager-applet numlockx playerctl polkit-gnome rofi scrot sysstat thunar thunar-archive-plugin thunar-volman tumbler unzip xarchiver xbindkeys xdg-user-dirs-gtk xed xfce4-terminal xorg-xbacklight xorg-xdpyinfo zip pavucontrol a52dec accountsservice alsa-firmware alsa-utils aspell bind chromaprint ding-libs dmidecode dmraid dnssec-anchors dracut duf faac ffmpegthumbnailer fluidsynth fsarchiver glances gssproxy gst-libav gst-plugins-bad gst-plugins-ugly gtksourceview3 haveged hdparm hwdetect hwinfo imagemagick inetutils inxi jemalloc less libavtp libdca libdvdcss libgme libgsf libinstpatch liblqr liblrdf libltc libmaxminddb libmbim libmicrodns libmpeg2 libopenraw libpipeline libqmi libqrtr-glib libwnck3 libx86emu libxres linux-headers logrotate lsb-release man-db man-pages meld mjpegtools modemmanager nano-syntax-highlighting net-tools netctl networkmanager-openconnect networkmanager-openvpn nfs-utils nfsidmap nss-mdns ntp oath-toolkit openconnect openh264 openvpn os-prober pacutils parallel perl-xml-writer pkcs11-helper pkgfile plocate poppler-glib ppp pv python-annotated-types python-defusedxml python-orjson python-pyaml python-pydantic python-pydantic-core python-pyqt5 python-pyqt5-sip python-typing_extensions qemu-guest-agent qrencode rebuild-detector rtmpdump s-nail sd sg3_utils soundtouch spandsp spice-vdagent svt-hevc systemd-resolvconf tcl ttf-bitstream-vera ttf-dejavu ttf-liberation ttf-opensans unrar usb_modeswitch usbutils
)

# Install general packages
install_if_needed "${packages[@]}"

# Ask user for gaming package installation
read -p "Do you want to install gaming packages? (y/n): " install_gaming
if [[ $install_gaming =~ ^[Yy]$ ]]; then
    install_if_needed "${gaming_packages[@]}"
else
    echo "Skipping gaming package installation."
fi

# Ask user to install i3wm specific packages
read -p "Do you want to install i3wm specific packages? (y/n): " install_i3wm
if [[ $install_i3wm =~ ^[Yy]$ ]]; then
    install_if_needed "${i3wm_packages[@]}"
else
    echo "Skipping i3wm package installation."
fi

# Restart xdg-desktop-portal services
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk

# Enable Bluetooth service and display a message
sudo systemctl enable bluetooth.service
echo "Bluetooth service has been enabled."

# Change default shell to zsh
chsh -s "$(which zsh)" "$USER"
