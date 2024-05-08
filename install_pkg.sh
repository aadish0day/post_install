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

# Define a function to install GTK Fonts
install_gtk() {
    echo "Installing Gtk Fonts..."
    ./gtk-theme.sh
}

# Define a function to install Icon theme
install_icon() {
    echo "Installing Icon theme..."
    ./icon_theme.sh
}

# Define a function to clone Neovim configuration
clone_neovim_config() {
    echo "Cloning Neovim configuration..."
    git clone https://github.com/Aadishx07/neovim_config.git "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
}

# Ensure the creation of the Screenshot folder
mkdir -p "$HOME/Pictures/Screenshots" || {
    echo "Failed to create $HOME/Pictures/Screenshots directory."
    exit 1
}

# Clone Neovim config
clone_neovim_config || {
    echo "Failed to clone Neovim configuration."
    exit 1
}

case $DISTRO_CHOICE in
    1)
        (cd debian && ./debian.sh) || {
            echo "Failed to run distribution specific script for Debian/Ubuntu."
            exit 1
        }
        ;;
    2)
        (cd arch && ./arch.sh) || {
            echo "Failed to run distribution specific script for Arch Linux."
            exit 1
        }
        ;;
    3)
        (cd fedora && ./fedora.sh) || {
            echo "Failed to run distribution specific script for Fedora."
            exit 1
        }
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

# Install fonts, icon themes, and GTK themes
install_nerd_fonts
install_icon
install_gtk

echo "Setup completed successfully!"

