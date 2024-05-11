#!/bin/bash

# Function to install yay
install_yay() {
	echo "yay could not be found, installing..."

	# Install necessary base-devel package group if not already installed
	if ! pacman -Qq base-devel &>/dev/null; then
		echo "Installing the base-devel package group..."
		sudo pacman -S --needed base-devel --noconfirm
	fi

	# Clone yay repository
	git clone https://aur.archlinux.org/yay.git
	if [ $? -ne 0 ]; then
		echo "Failed to clone yay repository."
		exit 1
	fi

	# Change directory to yay
	cd yay || exit

	# Build and install yay without confirmation
	makepkg -si --noconfirm

	# Clean up
	cd ..
	rm -rf yay

	echo "yay has been successfully installed."
}

# Check if yay is installed
if ! command -v yay &>/dev/null; then
	install_yay
else
	echo "yay is already installed."
fi

# Install packages
yay -S i3lock-color

yay -S thorium-browser-bin

yay -S vscodium-bin
yay -Rns vscodium-bin-debug

yay -S github-desktop-bin
yay -Rns github-desktop-bin-debug

yay -S moc

yay -S ani-cli

yay -S hakuneko-desktop

echo "Installation process completed!"
