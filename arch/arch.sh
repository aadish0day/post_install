#!/bin/bash

# This script updates the mirror list, system, and installs specified packages on Arch Linux

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Install reflector for managing mirror list
pacman -S --needed reflector --noconfirm || { echo "Failed to install reflector"; exit 1; }

# Configure mirrors for India using reflector
reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist || { echo "Failed to update mirror list"; exit 1; }

# Update system and packages
pacman -Syu --noconfirm || { echo "System update failed"; exit 1; }

# Function to check and install packages if they are not already installed
install_if_needed() {
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &> /dev/null; then
            echo "Installing $pkg..."
            pacman -S "$pkg" --noconfirm || { echo "Failed to install $pkg"; continue; }
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done
}

# List of packages to install
packages=(
    neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf htop doxygen flameshot npm xclip ueberzug highlight atool mediainfo neofetch android-tools img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman
)

# Install packages
install_if_needed "${packages[@]}"

# Enable bluetooth and display message
systemctl enable --now bluetooth.service && echo "Bluetooth service has been enabled."

echo "Installation and setup complete on Arch Linux."

