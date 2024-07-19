#!/usr/bin/env bash
set -euo pipefail

echo "Starting Arch Linux setup..."

# Update system and packages
sudo pacman -Sy --noconfirm

# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm

# Configure mirrors for India using reflector
sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Update system and packages
sudo pacman -Syu --noconfirm

# Function to check and install packages if they are not already installed
install_if_needed() {
	local pkg
	local failures=()
	local to_install=()

	# Prepare the list of packages to install
	for pkg in "$@"; do
		if ! pacman -Qi "$pkg" &>/dev/null; then
			to_install+=("$pkg")
		else
			echo "$pkg is already installed. Skipping..."
		fi
	done

	# Install missing packages if any
	if [ ${#to_install[@]} -gt 0 ]; then
		echo "Installing: ${to_install[*]}"
		if ! sudo pacman -S "${to_install[@]}" --noconfirm; then
			echo "Some packages failed to install, checking..."
			for pkg in "${to_install[@]}"; do
				if ! pacman -Qi "$pkg" &>/dev/null; then
					echo "Failed to install $pkg"
					failures+=("$pkg")
				fi
			done
			if [ ${#failures[@]} -gt 0 ]; then
				echo "Failed to install the following packages: ${failures[*]}"
				return 1
			fi
		fi
	fi
}

# List of packages to install, removing any duplicates
packages=(neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr)

# Install packages
install_if_needed "${packages[@]}"

# Enable Bluetooth and display message
sudo systemctl enable --now bluetooth.service
echo "Bluetooth service has been enabled."

echo "Changing default shell to zsh..."
chsh -s "$(which zsh)" "$USER"

# Ask if the user wants to install AMD drivers
read -p "Do you want to install AMD drivers? (y/n): " install_amd

if [[ "$install_amd" == "y" ]]; then
	# Update the system
	sudo pacman -Syu --noconfirm

	# Install necessary packages for AMD
	sudo pacman -S --noconfirm xf86-video-amdgpu amd-ucode vulkan-radeon lib32-vulkan-radeon linux-firmware radeontop lib32-mesa-vdpau mesa-vdpau

	# Create Xorg configuration if it doesn't exist
	if [ ! -f /etc/X11/xorg.conf.d/20-amdgpu.conf ]; then
		sudo mkdir -p /etc/X11/xorg.conf.d
		sudo tee /etc/X11/xorg.conf.d/20-amdgpu.conf >/dev/null <<EOL
Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"
    Option "VariableRefresh" "true"
EndSection
EOL
		echo "Xorg configuration for AMD created at /etc/X11/xorg.conf.d/20-amdgpu.conf."
	else
		echo "Xorg configuration file already exists at /etc/X11/xorg.conf.d/20-amdgpu.conf."
	fi

	# Edit GRUB configuration
	sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& quiet splash nowatchdog nvme_load=YES loglevel=3 amdgpu.dpm=1 amdgpu.audio=0 amdgpu.runpm=1 pcie_aspm=force radeon.si_support=0 radeon.cik_support=0/' /etc/default/grub

	# Update GRUB configuration
	sudo grub-mkconfig -o /boot/grub/grub.cfg

	echo "AMD drivers installed."
else
	echo "Skipping AMD driver installation."
fi

echo "Installation and setup complete on Arch Linux."
