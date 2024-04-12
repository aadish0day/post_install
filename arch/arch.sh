#!/bin/bash

# Update system and packages
sudo pacman -Syu --noconfirm

# Install reflector for managing mirror list
sudo pacman -S --needed reflector

# Configure mirrors for India
sudo reflector --latest 5 --country India --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Function to check and install packages if they are not already installed
install_if_needed() {
    for pkg in "$@"; do
        if ! pacman -Qi $pkg &> /dev/null; then
            echo "Installing $pkg..."
            sudo pacman -S --noconfirm $pkg
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done
}

# List of packages to install
packages=(
    neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf htop doxygen flameshot npm xclip ueberzug highlight atool mediainfo neofetch android-tools img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt
)

# Install packages
install_if_needed "${packages[@]}"

echo "Installation and setup complete on Arch Linux."

