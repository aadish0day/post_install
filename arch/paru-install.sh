#!/bin/bash

# Function to install paru
install_paru() {
	echo "paru could not be found, installing..."

	# Install necessary base-devel package group if not already installed
	if ! pacman -Qq base-devel &>/dev/null; then
		echo "Installing the base-devel package group..."
		sudo pacman -S --needed base-devel --noconfirm
	fi

	# Clone paru repository
	git clone https://aur.archlinux.org/paru.git
	if [ $? -ne 0 ]; then
		echo "Failed to clone paru repository."
		exit 1
	fi

	# Change directory to paru
	cd paru || exit

	# Build and install paru without confirmation
	makepkg -si --noconfirm

	# Clean up
	cd ..
	rm -rf paru

	echo "paru has been successfully installed."
}

# Check if paru is installed
if ! command -v paru &>/dev/null; then
	install_paru
else
	echo "paru is already installed."
fi

# List of general packages to install
general_packages=(
	"i3lock-color"
	"dracula-gtk-theme"
	"thorium-browser-bin"
	"vscodium-bin"
	"moc"
	"ueberzugpp"
	"ani-cli"
	"hakuneko-desktop-bin"
)

# List of ASUS specific packages to install
asus_packages=(
	"asusctl"
	"supergfxctl"
	"rog-control-center"
	"opencl-amd"
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
			paru -S --noconfirm "$package"
		else
			echo "$package is already installed."
		fi

		# Remove debug packages for -bin installations
		if [[ "$package" == *"-bin" ]]; then
			debug_package="${package%-bin}-debug"
			if pacman -Qi "$debug_package" &>/dev/null; then
				paru -Rns --noconfirm "$debug_package"
			fi
		fi
	done
}

echo "Installing general packages..."
install_packages "${general_packages[@]}"

# Ask if the user wants to install ASUS specific packages
read -rp "Do you want to install ASUS specific packages (asusctl, supergfxctl, rog-control-center)? (y/n): " install_asus

if [[ "$install_asus" == "y" ]]; then
	echo "Installing ASUS specific packages..."
	install_packages "${asus_packages[@]}"

	# Enable and start supergfxd service
	echo "Enabling and starting supergfxd service..."
	sudo systemctl enable --now supergfxd
else
	echo "Skipping ASUS specific packages."
fi

echo "Installation process completed!"
