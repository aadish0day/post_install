#!/bin/bash

# This script updates the mirror list, system, and installs specified packages on Arch Linux

# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm

# Configure mirrors for India
sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Update system and packages
sudo pacman -Syu --noconfirm

# Function to check and install packages if they are not already installed
install_if_needed() {
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &> /dev/null; then
            echo "Installing $pkg..."
            sudo pacman -S "$pkg" --noconfirm
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

echo "To enable bluetooth"
sudo systemctl enable --now bluetooth.service

echo "Installation and setup complete on Arch Linux."

