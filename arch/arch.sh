
#!/bin/bash

# Update system and packages
sudo pacman -Syu --noconfirm

# Install packages
sudo pacman -S --noconfirm neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf htop doxygen flameshot npm

# For AUR helper installation (yay or paru), uncomment and adjust the following:
# git clone https://aur.archlinux.org/yay.git
# cd yay
# makepkg -si
# cd ..
# rm -rf yay

echo "Install neovim config"
git clone https://github.com/Aadishx07/neovim_config.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim


echo "Installation and setup complete on Arch Linux."
