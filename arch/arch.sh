#!/usr/bin/env bash
set -e

echo "Starting Arch Linux setup..."

# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm || {
	echo "Failed to install reflector"
	exit 1
}

# Configure mirrors for India using reflector
sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist || {
	echo "Failed to update mirror list"
	exit 1
}

# Update system and packages
sudo pacman -Syu --noconfirm || {
	echo "System update failed"
	exit 1
}

# Function to check and install packages if they are not already installed
install_if_needed() {
	local failures=()
	for pkg in "$@"; do
		if ! pacman -Qi "$pkg" &>/dev/null; then
			echo "Installing $pkg..."
			sudo pacman -S "$pkg" --noconfirm || {
				echo "Failed to install $pkg"
				failures+=("$pkg")
				continue
			}
		else
			echo "$pkg is already installed. Skipping..."
		fi
	done
	if [ ${#failures[@]} -gt 0 ]; then
		echo "Failed to install the following packages: ${failures[*]}"
		return 1
	fi
}

# List of packages to install
packages=(
	neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs gcc make git ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip ueberzug highlight atool mediainfo neofetch android-tools img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman kitty
)

# Install packages
install_if_needed "${packages[@]}"

# Enable Bluetooth and display message
sudo systemctl enable --now bluetooth.service && echo "Bluetooth service has been enabled."

echo "Installation and setup complete on Arch Linux."
