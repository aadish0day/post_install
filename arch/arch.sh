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

# Update system and packages
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
    neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr mkinitcpio ttf-fira-mono papirus-icon-theme tree otf-firamono-nerd zoxide xdg-desktop-portal xdg-desktop-portal-gtk zed
)

# List of gaming packages to install
gaming_packages=(
    lutris wine wine-gecko wine-mono winetricks gamemode lib32-gamemode
    giflib lib32-giflib gnutls lib32-gnutls v4l-utils lib32-v4l-utils libpulse
    lib32-libpulse alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib
    sqlite lib32-sqlite libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd
    libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs
    vulkan-icd-loader lib32-vulkan-icd-loader sdl2 lib32-sdl2
)

# Install general packages
install_if_needed "${packages[@]}"

# Prompt user for gaming package installation
read -p "Do you want to install gaming packages? (y/n): " install_gaming
if [[ $install_gaming =~ ^[Yy]$ ]]; then
    install_if_needed "${gaming_packages[@]}"
fi

# Restart xdg-desktop-portal services
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk

# Enable Bluetooth service and display a message
sudo systemctl enable bluetooth.service
echo "Bluetooth service has been enabled."

# Change default shell to zsh
chsh -s "$(which zsh)" "$USER"
