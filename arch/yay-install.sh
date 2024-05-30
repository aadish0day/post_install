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

# List of packages to install
packages=(
	"i3lock-color"
	"thorium-browser-bin"
	"vscodium-bin"
	"github-desktop-bin"
	"moc"
	"ueberzugpp"
	"ani-cli"
	"hakuneko-desktop"
)

# Handle conflicting packages
conflicts=(
	"i3lock:i3lock-color"
)

for conflict in "${conflicts[@]}"; do
	to_remove="${conflict%%:*}"
	to_install="${conflict##*:}"
	if pacman -Qq "$to_remove" &>/dev/null; then
		sudo pacman -Rns --noconfirm "$to_remove"
	fi
	yay -S --noconfirm "$to_install"
	if [[ "$to_install" == *"-bin" ]]; then
		debug_package="${to_install}-debug"
		yay -Rns --noconfirm "$debug_package"
	fi
done

# Install other packages
for package in "${packages[@]}"; do
	if ! pacman -Qq "$package" &>/dev/null; then
		yay -S --noconfirm "$package"
		if [[ "$package" == *"-bin" ]]; then
			debug_package="${package}-debug"
			yay -Rns --noconfirm "$debug_package"
		fi
	fi
done

echo "Installation process completed!"
