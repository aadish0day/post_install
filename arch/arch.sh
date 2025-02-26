#!/usr/bin/env bash
set -euo pipefail

# Update system and packages
echo "Updating system and packages..."
sudo pacman -Sy --noconfirm
sudo pacman -S --needed reflector --noconfirm

# Prompt user to configure mirrors
read -rp "Do you want to configure the mirror list for India using reflector? (y/n): " configure_mirrors
if [[ $configure_mirrors =~ ^[Yy]$ ]]; then
    echo "Configuring mirror list for India..."
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
        if ! sudo pacman -S --noconfirm --needed "${to_install[@]}"; then
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

# Function to install paru
install_paru() {
    echo "Installing paru..."
    if ! pacman -Qq base-devel &>/dev/null; then
        echo "Installing base-devel package group..."
        sudo pacman -S --needed base-devel git --noconfirm
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || exit 1

    if ! git clone https://aur.archlinux.org/paru-bin.git; then
        echo "Failed to clone paru-bin repository."
        cd - || exit 1
        rm -rf "$temp_dir"
        return 1
    fi

    cd paru-bin || {
        echo "Failed to enter paru-bin directory."
        cd - || exit 1
        rm -rf "$temp_dir"
        return 1
    }

    makepkg -si --noconfirm || {
        echo "Failed to build and install paru."
        cd - || exit 1
        rm -rf "$temp_dir"
        return 1
    }

    cd - || exit 1
    rm -rf "$temp_dir"
    echo "paru has been successfully installed."
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

# List of general packages
packages=(
    neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop
    gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch
    android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb
    obs-studio picom nitrogen starship xss-lock qalculate-qt flatpak
    brightnessctl qbittorrent bluez bluez-utils blueman bat zsh jpegoptim zip
    tar p7zip zstd lz4 xz trash-cli mkinitcpio papirus-icon-theme tree zoxide
    ueberzugpp ttf-hack-nerd lsd noto-fonts noto-fonts-cjk noto-fonts-emoji
    noto-fonts-extra kitty ttf-jetbrains-mono ttf-jetbrains-mono-nerd
)

# List of gaming packages
gaming_packages=(
    wine-staging lutris wine-gecko wine-mono winetricks gamemode lib32-gamemode giflib
    lib32-giflib gnutls lib32-gnutls v4l-utils lib32-v4l-utils libpulse lib32-libpulse
    alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite
    libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva lib32-libva gtk3
    lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader
    lib32-vulkan-icd-loader sdl2 lib32-sdl2 innoextract libayatana-appindicator
    lib32-vkd3d python-protobuf vkd3d
)

# List of i3wm packages
tilling_depen=(
    acpi arandr archlinux-xdg-menu awesome-terminal-fonts dex dmenu dunst feh gvfs autotiling
    gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb jq
    nwg-look mpv network-manager-applet numlockx playerctl rofi scrot
    sysstat thunar thunar-archive-plugin thunar-volman tumbler unzip xarchiver xbindkeys
    xdg-user-dirs-gtk xfce4-terminal xorg-xbacklight xorg-xdpyinfo zip pavucontrol
    accountsservice alsa-firmware alsa-utils chromaprint ding-libs dmidecode
    dmraid dnssec-anchors dracut duf ffmpegthumbnailer fluidsynth fsarchiver
    gssproxy gst-libav gst-plugins-ugly gtksourceview3 haveged hdparm
    hwdetect hwinfo imagemagick inetutils inxi jemalloc less libavtp libdca libgme
    libgsf libinstpatch liblqr liblrdf libltc libmaxminddb libmbim
    libopenraw libpipeline libqmi libqrtr-glib libwnck3 libx86emu libxres
    linux-headers logrotate lsb-release man-db man-pages mjpegtools modemmanager netctl
    ntp os-prober pacutils parallel perl-xml-writer pkgfile plocate poppler-glib ppp pv
    python-annotated-types python-defusedxml python-orjson python-pyaml
    python-pydantic python-pydantic-core python-pyqt5 python-pyqt5-sip
    python-typing_extensions sd sg3_utils soundtouch spandsp
    svt-hevc systemd-resolvconf tcl ttf-opensans usb_modeswitch usbutils clipmenu tldr
    polybar xdg-desktop-portal xdg-desktop-portal-gtk
)

# List of AUR packages
aur_packages=(
    "thorium-browser-bin"
    "i3lock-color"
    "brn2-git"
    "dxvk-bin"
    # "rofi-greenclip"
    "dracula-gtk-theme"
    "vscodium-bin"
    "moc"
    "ani-cli"
    "hakuneko-desktop"
)

# List of ASUS specific packages
asus_packages=(
    "vulkan-amdgpu-pro"
    "lib32-vulkan-amdgpu-pro"
    "amdgpu-pro-oglp"
    "lib32-amdgpu-pro-oglp"
    "opencl-headers"
    "amf-amdgpu-pro"
    # "opencl-amd"
)

# Install base packages
echo "Installing base packages..."
install_if_needed "${packages[@]}"

# Ask user for gaming package installation
read -rp "Do you want to install gaming packages? (y/n): " install_gaming
if [[ $install_gaming =~ ^[Yy]$ ]]; then
    install_if_needed "${gaming_packages[@]}"
else
    echo "Skipping gaming package installation."
fi

# Ask user to install i3wm specific packages
read -rp "Do you want to install tilling specific packages? (y/n): " install_tilling
if [[ $install_tilling =~ ^[Yy]$ ]]; then
    install_if_needed "${tilling_depen[@]}"
else
    echo "Skipping i3wm package installation."
fi

# Install paru if not present
if ! command -v paru &>/dev/null; then
    install_paru || {
        echo "Failed to install paru. AUR packages will not be installed."
        exit 1
    }
fi

# Install AUR packages
echo "Installing AUR packages..."
install_aur_packages "${aur_packages[@]}"

# Ask if the user wants to install ASUS specific packages
read -rp "Do you want to install ASUS specific drivers? (y/n): " install_asus
if [[ $install_asus =~ ^[Yy]$ ]]; then
    install_aur_packages "${asus_packages[@]}"
else
    echo "Skipping ASUS specific packages."
fi

echo "install flatpak app"
flatpak install flathub org.libreoffice.LibreOffice

# Enable and restart services
echo "Enabling and starting services..."
sudo systemctl enable --now bluetooth.service
systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service

echo "zathura set to default"
xdg-mime default org.pwmt.zathura.desktop application/pdf

# Set thorium-browser as default browser if installed
if command -v thorium-browser &>/dev/null; then
    echo "Setting thorium-browser as the default browser..."
    xdg-settings set default-web-browser thorium-browser.desktop
    current_browser=$(xdg-settings get default-web-browser)
    echo "Current default browser: $current_browser"
fi

# Change default shell to zsh if installed
if command -v zsh &>/dev/null; then
    echo "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)" "$USER"
fi

echo "Installation process completed! Please reboot your system."
