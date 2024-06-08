#!/bin/bash

# Prompt user to select their distribution
echo "Select your distribution:"
echo "1) Debian/Ubuntu"
echo "2) Arch Linux"
echo "3) Fedora"
read -p "Distribution (1/2/3): " DISTRO_CHOICE

# Define a function to install Nerd Fonts
#install_nerd_fonts() {
#	echo "Installing Nerd Fonts..."
#	if [ -f "./nerd_font.sh" ]; then
#		./nerd_font.sh || {
#			echo "Failed to install Nerd Fonts."
#			exit 1
#		}
#	else
#		echo "nerd_font.sh script not found."
#		exit 1
#	fi
#}

# Define a function to install GTK Fonts
install_gtk() {
	echo "Installing Gtk Fonts..."
	if [ -f "./gtk-theme.sh" ]; then
		./gtk-theme.sh || {
			echo "Failed to install Gtk Fonts."
			exit 1
		}
	else
		echo "gtk-theme.sh script not found."
		exit 1
	fi
}

# Define a function to install Icon theme
install_icon() {
	echo "Installing Icon theme..."
	if [ -f "./icon_theme.sh" ]; then
		./icon_theme.sh || {
			echo "Failed to install Icon theme."
			exit 1
		}
	else
		echo "icon_theme.sh script not found."
		exit 1
	fi
}

# Define a function to clone Neovim configuration
clone_neovim_config() {
	echo "Cloning Neovim configuration..."
	git clone https://github.com/Aadishx07/neovim_config.git "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" || {
		echo "Failed to clone Neovim configuration."
		exit 1
	}
}

# Ensure the creation of the Screenshot folder
mkdir -p "$HOME/Pictures/Screenshots" || {
	echo "Failed to create $HOME/Pictures/Screenshots directory."
	exit 1
}

# Clone Neovim config
clone_neovim_config

# Run the distribution-specific script
case $DISTRO_CHOICE in
1)
	if [ -d "./debian" ] && [ -f "./debian/debian.sh" ]; then
		(cd debian && ./debian.sh) || {
			echo "Failed to run distribution-specific script for Debian/Ubuntu."
			exit 1
		}
	else
		echo "Debian/Ubuntu script not found."
		exit 1
	fi
	;;
2)
	if [ -d "./arch" ] && [ -f "./arch/arch.sh" ]; then
		(cd arch && ./arch.sh) || {
			echo "Failed to run distribution-specific script for Arch Linux."
			exit 1
		}
	else
		echo "Arch Linux script not found."
		exit 1
	fi
	;;
3)
	if [ -d "./fedora" ] && [ -f "./fedora/fedora.sh" ]; then
		(cd fedora && ./fedora.sh) || {
			echo "Failed to run distribution-specific script for Fedora."
			exit 1
		}
	else
		echo "Fedora script not found."
		exit 1
	fi
	;;
*)
	echo "Invalid selection. Exiting."
	exit 1
	;;
esac

# Install fonts, icon themes, and GTK themes
#install_nerd_fonts
install_icon
install_gtk

echo "Setup completed successfully!"
