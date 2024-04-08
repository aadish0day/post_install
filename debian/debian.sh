#!/bin/bash

# Exit on any error
set -e

# Ensure nala is installed (this uses apt since nala might not be installed yet)
sudo apt update && sudo apt install -y nala

# Update the system
echo "Updating the system..."
sudo nala update && sudo nala upgrade

# Install software-properties-common if not already installed (for add-apt-repository)
sudo nala install -y software-properties-common

# Install packages
echo "Installing packages..."
sudo nala install -y ranger ncdu mpv maven yt-dlp htop fzf git unzip nodejs flameshot xclip ueberzug highlight atool mediainfo neofetch android-tools-adb android-tools-fastboot img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock 

# For yt-dlp, if not available directly through nala, you might still need to install it via pip or another method
# Ensure Python3-pip is installed
sudo nala install -y python3-pip
# Install yt-dlp using pip
pip3 install yt-dlp

echo "install neovim dependencies"
sudo nala install -y ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen npm

echo "install neovim from source"
sudo ./compile_neovim.sh

echo "install starship on the system"
curl -sS https://starship.rs/install.sh | sh 

echo "Installation and setup complete on debian Linux."
