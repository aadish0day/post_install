
#!/bin/bash

# Update system and packages
sudo pacman -Syu --noconfirm

# Install packages
sudo pacman -S --noconfirm neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf doxygen

# For AUR helper installation (yay or paru), uncomment and adjust the following:
# git clone https://aur.archlinux.org/yay.git
# cd yay
# makepkg -si
# cd ..
# rm -rf yay

# Clone and set up NvChad for Neovim
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/NvChad/NvChad ~/.config/nvim --depth 1
    echo "NvChad setup complete. Launching Neovim to finalize setup..."
    # Launch Neovim to complete setup; this can be commented out for non-interactive runs
    nvim
else
    echo "NvChad is already set up."
fi

echo "Installation and setup complete on Arch Linux."
