#!/bin/bash

# Prompt user to select their distribution
echo "Select your distribution:"
echo "1) Debian/Ubuntu"
echo "2) Arch Linux"
echo "3) Fedora"
echo "4) Kali Linux"
read -p "Distribution (1/2/3/4): " DISTRO_CHOICE

# Define a function to clone Neovim configuration
clone_neovim_config() {
	echo "Cloning Neovim configuration..."
	if git clone https://github.com/Aadishx07/neovim_config.git "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"; then
		echo "Neovim configuration cloned successfully."
	else
		echo "Failed to clone Neovim configuration."
		exit 1
	fi
}

# Check if Neovim config already exists
if [ ! -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" ]; then
	# Clone Neovim config if it doesn't exist
	clone_neovim_config
else
	echo "Neovim configuration already exists. Skipping clone."
fi

# Ensure the creation of the Screenshot folder
mkdir -p "$HOME/Pictures/Screenshots" || {
	echo "Failed to create $HOME/Pictures/Screenshots directory."
	exit 1
}

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
4)
	if [ -d "./kali" ] && [ -f "./kali/kali.sh" ]; then
		(cd kali && ./kali.sh) || {
			echo "Failed to run distribution-specific script for Kali Linux."
			exit 1
		}
	else
		echo "Kali Linux script not found."
		exit 1
	fi
	;;
*)
	echo "Invalid selection. Exiting."
	exit 1
	;;
esac

# Install fonts, icon themes, and GTK themes
echo "Setup completed successfully!"
