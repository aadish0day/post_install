#!/bin/bash

# Function to install paru
install_paru() {
	echo "Installing paru..."

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

# Function to install yay
install_yay() {
	echo "Installing yay..."

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

# Ask if the user wants to install paru or yay
read -rp "Do you want to install paru or yay? (p/y): " aur_helper

if ! command -v paru &>/dev/null && ! command -v yay &>/dev/null; then
	if [[ "$aur_helper" == "p" ]]; then
		install_paru
	elif [[ "$aur_helper" == "y" ]]; then
		install_yay
	else
		echo "Invalid choice, exiting..."
		exit 1
	fi
else
	echo "An AUR helper is already installed."
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
	"vulkan-amdgpu-pro"
	"lib32-vulkan-amdgpu-pro"
	"amdgpu-pro-oglp"
	"lib32-amdgpu-pro-oglp"
	"opencl-headers"
	"amf-amdgpu-pro"
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
			if command -v paru &>/dev/null; then
				paru -S --noconfirm "$package"
			elif command -v yay &>/dev/null; then
				yay -S --noconfirm "$package"
			fi
		else
			echo "$package is already installed."
		fi

		# Remove debug packages for -bin installations
		if [[ "$package" == *"-bin" ]]; then
			debug_package="${package%-bin}-debug"
			if pacman -Qi "$debug_package" &>/dev/null; then
				if command -v paru &>/dev/null; then
					paru -Rns --noconfirm "$debug_package"
				elif command -v yay &>/dev/null; then
					yay -Rns --noconfirm "$debug_package"
				fi
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
