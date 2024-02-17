#!/bin/bash

# Update package lists
sudo apt update

# Install Nala, an improved APT package manager
sudo apt install -y nala

# Use Nala to install required packages
sudo nala install -y ranger moc ncdu mpv maven yt-dlp fzf ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen git nodejs flameshot

# Clone and compile Neovim
sudo ./compile_neovim.sh

# Clone and setup NvChad for Neovim
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/NvChad/NvChad ~/.config/nvim --depth 1
    echo "Launching Neovim for the first time setup. Please follow any on-screen instructions."
    nvim
else
    echo "NvChad appears to be already set up."
fi

echo "Debian/Ubuntu installation complete."
