#!/bin/bash

echo "Select your distribution:"
echo "1) Debian/Ubuntu"
echo "2) Arch Linux"
echo "3) Fedora"
read -p "Distribution (1/2/3): " DISTRO_CHOICE

# Define a function to install Nerd Fonts
install_nerd_fonts() {
  echo "Installing Nerd Fonts..."
  ./nerd_font.sh
}

# Define a function to clone Neovim configuration
clone_neovim_config() {
  echo "Cloning Neovim configuration..."
  git clone https://github.com/Aadishx07/neovim_config.git "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
}

# Clone Neovim configuration before proceeding with the installation
clone_neovim_config

case $DISTRO_CHOICE in
  1)
    cd debian && ./debian.sh && cd ..
    install_nerd_fonts
    ;;
  2)
    cd arch && ./arch.sh && cd ..
    install_nerd_fonts
    ;;
  3)
    cd fedora && ./fedora.sh && cd ..
    install_nerd_fonts
    ;;
  *)
    echo "Invalid selection. Exiting."
    exit 1
    ;;
esac

