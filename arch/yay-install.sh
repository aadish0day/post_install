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

# List of general packages to install
general_packages=(
	"i3lock-color"
	"thorium-browser-bin"
	"vscodium-bin"
	"github-desktop-bin"
	"moc"
	"ueberzugpp"
	"ani-cli"
	"hakuneko-desktop"
)

# List of ASUS specific packages to install
asus_packages=(
	"asusctl"
	"supergfxctl"
	"rog-control-center"
)

# Function to install packages
install_packages() {
	local packages=("$@")
	for package in "${packages[@]}"; do
		if ! pacman -Qi "$package" &>/dev/null; then
			# Handle conflicts
			if [[ "$package" == "i3lock-color" ]]; then
				if pacman -Qq "i3lock" &>/dev/null; then
					sudo pacman -Rns --noconfirm "i3lock"
				fi
			fi
			# Install package
			yay -S --noconfirm "$package"
		else
			echo "$package is already installed."
		fi

		# Remove debug packages for -bin installations
		if [[ "$package" == *"-bin" ]]; then
			debug_package="${package%-bin}-debug"
			if pacman -Qi "$debug_package" &>/dev/null; then
				yay -Rns --noconfirm "$debug_package"
			fi
		fi
	done
}

echo "Installing general packages..."
install_packages "${general_packages[@]}"

# Ask if the user wants to install ASUS specific packages
read -rp "Do you want to install ASUS specific packages (asusctl, supergfxctl, rog-control-center)? (yes/no): " install_asus

if [[ "$install_asus" == "yes" ]]; then
	echo "Installing ASUS specific packages..."
	install_packages "${asus_packages[@]}"
else
	echo "Skipping ASUS specific packages."
fi

echo "Installation process completed!"
