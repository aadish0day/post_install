#!/bin/bash

# Exit on any error
set -e

# Install Nala, an improved APT package manager
sudo apt install -y nala

# Update the system
echo "Updating the system..."
sudo nala update && sudo nala upgrade

# Install software-properties-common if not already installed (for add-apt-repository)
sudo nala install -y software-properties-common

# Install packages
echo "Installing packages..."
sudo nala install -y ranger ncdu mpv neovim maven yt-dlp fzf git unzip nodejs flameshot

# For yt-dlp, if not available directly through nala, you might still need to install it via pip or another method
# Ensure Python3-pip is installed
sudo nala install -y python3-pip
# Install yt-dlp using pip
pip3 install yt-dlp

echo "install neovim from source"
sudo ./compile_neovim.sh

# Clone NvChad for Neovim setup
echo "Cloning NvChad for Neovim setup..."
git clone https://github.com/NvChad/NvChad ~/.config/nvim --depth 1 || { echo "NvChad clone failed. It might already be installed, or there's a network issue."; }

echo "Setup complete. Please consider reviewing and customizing your Neovim setup as needed."
