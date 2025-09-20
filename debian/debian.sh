#!/usr/bin/env bash

# Exit on any error
set -e

# Ensure nala is installed
echo "Ensuring nala is installed..."
sudo apt update && sudo apt install -y nala

# Update the system
echo "Updating the system..."
sudo nala update && sudo nala upgrade -y

# Install software-properties-common if not already installed
echo "Installing software-properties-common..."
sudo nala install -y software-properties-common

# Install required packages
echo "Installing packages..."
sudo nala install -y ranger ncdu mpv maven yt-dlp htop fzf git unzip nodejs flameshot xclip ueberzug highlight atool mediainfo android-tools-adb android-tools-fastboot img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock qalculate-gtk libreoffice bluez bat alacritty jpegoptim zip unzip tar p7zip zstd lz4 xz-utils trash-cli lxrandr

# Install Python3-pip if not already installed
echo "Installing Python3-pip..."
sudo nala install -y python3-pip

# Install Starship if not already installed
if ! command -v starship &>/dev/null; then
	echo "Installing Starship..."
	curl -sS https://starship.rs/install.sh | sh
else
	echo "Starship is already installed."
fi

echo "Installation and setup complete on Debian Linux."
