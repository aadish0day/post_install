#!/usr/bin/env bash
set -euo pipefail

# Keep sudo alive during long operations (e.g., AUR builds)
if sudo -v; then
    sudo -n true
    keep_sudo_alive() { while true; do
        sleep 60
        sudo -n true
    done; }
    keep_sudo_alive &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill ${SUDO_KEEP_ALIVE_PID} 2>/dev/null || true' EXIT
fi

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

# ============================================================================
# ASK USER PREFERENCES UPFRONT
# ============================================================================

echo ""
echo "=========================================="
echo "Desktop Environment Selection"
echo "=========================================="
echo "1) KDE Plasma"
echo "2) X11 Tiling Window Manager"
echo "3) None (Skip desktop environment)"
echo ""
read -rp "Select desktop environment (1-3): " de_choice

install_kde=false
install_x11=false

case $de_choice in
1)
    install_kde=true
    echo "KDE Plasma will be installed."
    ;;
2)
    install_x11=true
    echo "X11 tiling window manager packages will be installed."
    ;;
3)
    echo "Skipping desktop environment installation."
    ;;
*)
    echo "Invalid choice. Skipping desktop environment installation."
    ;;
esac

# Ask about gaming packages
echo ""
read -rp "Do you want to install gaming packages? (y/n): " install_gaming_input
install_gaming=false
if [[ $install_gaming_input =~ ^[Yy]$ ]]; then
    install_gaming=true
    echo "Gaming packages will be installed."
else
    echo "Skipping gaming packages."
fi

# Ask about ASUS specific packages
echo ""
read -rp "Do you want to install ASUS specific drivers? (y/n): " install_asus_input
install_asus=false
if [[ $install_asus_input =~ ^[Yy]$ ]]; then
    install_asus=true
    echo "ASUS specific drivers will be installed."
else
    echo "Skipping ASUS specific drivers."
fi

# Ask about virtualization packages
echo ""
read -rp "Do you want to install virtualization packages (VMware Workstation and Open VM Tools)? (y/n): " install_virt_input
install_virt=false
if [[ $install_virt_input =~ ^[Yy]$ ]]; then
    install_virt=true
    echo "Virtualization packages will be installed."
else
    echo "Skipping virtualization packages."
fi

# Ask about AMD GPU drivers and related runtimes
echo ""
read -rp "Do you want to install AMD GPU drivers and runtimes (Vulkan/OpenCL/VA-API/VDPAU)? (y/n): " install_amd_input
install_amd=false
if [[ $install_amd_input =~ ^[Yy]$ ]]; then
    install_amd=true
    echo "AMD GPU drivers and runtimes will be installed."
else
    echo "Skipping AMD GPU drivers and runtimes."
fi

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
# Determine which desktop environment was selected
de_name="None"
if [ "$install_kde" = true ]; then
    de_name="KDE Plasma"
elif [ "$install_x11" = true ]; then
    de_name="X11 Tiling"
fi

echo "Desktop Environment: $de_name"
echo "Gaming Packages: $([ "$install_gaming" = true ] && echo "Yes" || echo "No")"
echo "ASUS Drivers: $([ "$install_asus" = true ] && echo "Yes" || echo "No")"
echo "Virtualization Packages: $([ "$install_virt" = true ] && echo "Yes" || echo "No")"
echo "AMD Drivers: $([ "$install_amd" = true ] && echo "Yes" || echo "No")"
echo "=========================================="
echo ""
read -rp "Continue with installation? (y/n): " continue_install
if [[ ! $continue_install =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# ============================================================================
# FUNCTIONS
# ============================================================================

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

    cd /tmp || exit 1

    if [ -d "/tmp/paru-bin" ]; then
        echo "Removing existing paru-bin directory..."
        rm -rf /tmp/paru-bin
    fi

    if ! git clone https://aur.archlinux.org/paru-bin.git; then
        echo "Failed to clone paru-bin repository."
        cd - || exit 1
        return 1
    fi

    cd paru-bin || {
        echo "Failed to enter paru-bin directory."
        cd - || exit 1
        return 1
    }

    makepkg -si --noconfirm || {
        echo "Failed to build and install paru."
        cd - || exit 1
        return 1
    }

    cd - || exit 1
    rm -rf /tmp/paru-bin
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

# ============================================================================
# PACKAGE LISTS
# ============================================================================

# List of general packages
packages=(
    android-tools aria2 atool bat cantarell-fonts chromaprint doxygen duf fastfetch fd ffmpegthumbnailer
    fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs
    gvfs-smb highlight htop img2pdf imagemagick inxi jq jpegoptim kitty less libavtp libdca libgme liblrdf libltc
    libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv mpv-mpris ncdu
    neovim nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra npm obs-studio p7zip pacman-contrib pacutils
    papirus-icon-theme parallel pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse pipewire-zeroconf
    pkgfile plocate playerctl pv qalculate-qt qbittorrent ripgrep sd spandsp starship soundtouch svt-hevc tar
    tree tree-sitter-cli trash-cli tmux ttf-jetbrains-mono ttf-jetbrains-mono-nerd tumbler unzip wireplumber xz
    yazi yt-dlp zathura zathura-cb zathura-djvu zathura-pdf-poppler zathura-ps zip zoxide zsh zstd dosfstools
    usbutils
)

# List of gaming packages
gaming_packages=(
    alsa-lib alsa-plugins gamemode giflib gnutls gst-plugins-base-libs gtk3 innoextract
    lib32-alsa-lib lib32-alsa-plugins lib32-gamemode lib32-giflib lib32-gnutls
    lib32-gst-plugins-base-libs lib32-gtk3 lib32-libpulse lib32-libva lib32-libxcomposite
    lib32-ocl-icd lib32-sdl2 lib32-sqlite lib32-v4l-utils lib32-vkd3d lib32-vulkan-icd-loader
    libayatana-appindicator libpulse libva libxcomposite ocl-icd python-protobuf sdl2 sqlite
    v4l-utils vkd3d vulkan-icd-loader wine-gecko wine-mono wine-staging winetricks
)

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
)

# List of KDE Plasma desktop environment packages
kde_plasma_packages=(
    rsync obsidian elisa gwenview kamoso okular libreoffice-fresh wl-clipboard qt6-tools
    mesa libva-mesa-driver libva-utils vulkan-radeon vulkan-tools dosfstools sshfs kdeconnect
)

# List of AUR packages
aur_packages=(
    "thorium-browser-bin"
    "advcpmv"
    "ani-cli"
    "hakuneko-desktop"
    "vesktop-bin"
    "visual-studio-code-bin"
    "spotify"
)

# List of X11-specific AUR packages
x11_aur_packages=(
    "i3lock-color"
    "dracula-gtk-theme"
)

# List of gaming-specific AUR packages
gaming_aur_packages=(
    "dxvk-bin"
)

# List of ASUS specific packages
asus_packages=(
    "vulkan-amdgpu-pro"
    "lib32-vulkan-amdgpu-pro"
    "amdgpu-pro-oglp"
    "lib32-amdgpu-pro-oglp"
    "opencl-headers"
    "amf-amdgpu-pro"
)

# List of AMD GPU and related runtime packages
amd_packages=(
    xf86-video-amdgpu amd-ucode mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
    radeontop libva-mesa-driver lib32-libva-mesa-driver mesa-utils mesa-demos
    vulkan-mesa-layers lib32-mesa-utils lib32-mesa-demos lib32-vulkan-mesa-layers
    rocm-opencl-runtime rocm-opencl-sdk opencl-headers libclc ocl-icd glu lib32-glu
    mesa-vdpau lib32-mesa-vdpau
)

# List of virtualization packages
virt_packages=(
    "libx11-mr293"
    "vmware-workstation"
    #    "open-vm-tools"
)

# ============================================================================
# INSTALLATION
# ============================================================================

# Install base packages
echo ""
echo "Installing base packages..."
install_if_needed "${packages[@]}"

# Initialize Git LFS for the current user
if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
    echo "Initializing Git LFS..."
    git lfs install --skip-repo
fi

if [ "$install_amd" = true ]; then
    echo ""
    echo "Installing AMD GPU drivers and runtimes..."
    install_if_needed "${amd_packages[@]}"

    # Edit GRUB configuration to optimize for AMD
    echo "Editing GRUB configuration..."
    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 amd_pstate=active amd_prefcore=enable"|' /etc/default/grub

    # Regenerate the GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

# Install gaming packages if selected
if [ "$install_gaming" = true ]; then
    echo ""
    echo "Installing gaming packages..."
    install_if_needed "${gaming_packages[@]}"
fi

# Install X11 tiling-specific packages if selected
if [ "$install_x11" = true ]; then
    echo ""
    echo "Installing X11 tiling-specific packages..."
    install_if_needed "${x11_tilling_depen[@]}"
fi

# Install KDE Plasma desktop environment if selected
if [ "$install_kde" = true ]; then
    echo ""
    echo "Installing KDE Plasma desktop environment..."
    install_if_needed "${kde_plasma_packages[@]}"
fi

# Install paru if not present
if ! command -v paru &>/dev/null; then
    echo ""
    install_paru || {
        echo "Failed to install paru. AUR packages will not be installed."
        exit 1
    }
fi

# Install AUR packages
echo ""
echo "Installing AUR packages..."
install_aur_packages "${aur_packages[@]}"

# Install X11-specific AUR packages if selected
if [ "$install_x11" = true ]; then
    echo ""
    echo "Installing X11-specific AUR packages..."
    install_aur_packages "${x11_aur_packages[@]}"
fi

# Install gaming-specific AUR packages if selected
if [ "$install_gaming" = true ]; then
    echo ""
    echo "Installing gaming-specific AUR packages..."
    install_aur_packages "${gaming_aur_packages[@]}"
fi

# Install ASUS specific packages if selected
if [ "$install_asus" = true ]; then
    echo ""
    echo "Installing ASUS specific drivers..."
    install_aur_packages "${asus_packages[@]}"
fi

# Install virtualization packages if selected
if [ "$install_virt" = true ]; then
    echo ""
    echo "Installing virtualization packages..."
    install_aur_packages "${virt_packages[@]}"
fi

# ============================================================================
# SERVICE CONFIGURATION
# ============================================================================

echo ""
echo "Configuring services..."

# Enable Bluetooth if X11 tiling is installed (KDE manages its own Bluetooth)
if [ "$install_x11" = true ]; then
    read -rp "Do you want to enable Bluetooth? (y/n): " enable_bluetooth
    if [[ $enable_bluetooth =~ ^[Yy]$ ]]; then
        sudo systemctl enable --now bluetooth.service
        echo "Bluetooth service enabled."
    fi
fi

# Enable dbus (skip for KDE as it handles this)
if [ "$install_kde" = false ]; then
    if systemctl list-unit-files | grep -q "dbus-broker.service"; then
        systemctl --user enable --now dbus-broker.service
    elif systemctl list-unit-files | grep -q "dbus-daemon.service"; then
        systemctl --user enable --now dbus-daemon.service
    else
        echo "No dbus backend service found, skipping..."
    fi
fi

# Enable SDDM if KDE Plasma is installed
if [ "$install_kde" = true ] && pacman -Qi sddm &>/dev/null; then
    if ! systemctl is-enabled sddm.service &>/dev/null; then
        echo "Enabling SDDM display manager..."
        sudo systemctl enable sddm.service
    else
        echo "SDDM is already enabled."
    fi
fi

# Start xdg-desktop-portal services (don't enable, they're socket-activated)
systemctl_user_services=(
    "xdg-desktop-portal.service"
    "xdg-desktop-portal-gtk.service"
)

for service in "${systemctl_user_services[@]}"; do
    if systemctl --user list-unit-files | grep -q "$service"; then
        if ! systemctl --user is-active --quiet "$service"; then
            systemctl --user start "$service" 2>/dev/null && echo "Started $service" || true
        fi
    fi
done

# ============================================================================
# DEFAULT APPLICATIONS
# ============================================================================

echo ""
echo "Configuring default applications..."

# Set Zathura as default PDF viewer for X11
if [ "$install_x11" = true ]; then
    if command -v zathura &>/dev/null; then
        echo "Setting Zathura as the default PDF viewer..."
        xdg-mime default org.pwmt.zathura.desktop application/pdf
    else
        echo "Zathura is not installed; skipping default PDF assignment."
    fi
fi

# Set thorium-browser as default browser if installed
if command -v thorium-browser &>/dev/null; then
    echo "Setting thorium-browser as the default browser..."
    xdg-settings set default-web-browser thorium-browser.desktop 2>/dev/null || true
    current_browser=$(xdg-settings get default-web-browser 2>/dev/null)
    if [ -n "$current_browser" ]; then
        echo "Current default browser: $current_browser"
    fi
fi

# Change default shell to zsh if installed
if command -v zsh &>/dev/null; then
    read -rp "Do you want to change your default shell to zsh? (y/n): " change_shell
    if [[ $change_shell =~ ^[Yy]$ ]]; then
        echo "Changing default shell to zsh..."
        chsh -s "$(command -v zsh)" "$USER"
        echo "Default shell changed to zsh. Please log out and log back in for changes to take effect."
    fi
fi

echo ""
echo "=========================================="
echo "Installation completed successfully!"
echo "=========================================="
echo "Please reboot your system for all changes to take effect."
