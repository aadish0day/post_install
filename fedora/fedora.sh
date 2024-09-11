#!/bin/bash

# Set strict error handling
set -eo pipefail

# Function to log script actions
log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Update the dnf config
sudo cp -r ./dnf.conf /etc/dnf/dnf.conf

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
	log "This script must be run as root"
	exit 1
fi

log "Starting Fedora setup..."

# Update the system
log "Updating the system..."
dnf update -y

# Install RPM Fusion repositories
log "Installing RPM Fusion repositories..."
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
	"https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Install essential packages
log "Installing essential packages..."
dnf install -y neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd-find unzip htop gettext libtool \
	doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools zathura zathura-pdf-mupdf \
	zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock qalculate-qt libreoffice brightnessctl \
	qbittorrent bluez blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr wine winetricks \
	gamemode lutris papirus-icon-theme tree

# Enable COPR and install starship
log "Enabling COPR for starship..."
dnf copr enable atim/starship -y
log "Installing starship..."
dnf install -y starship

# Install Python utilities with pip
log "Installing Python utilities with pip..."
dnf install -y python3-pip
pip install img2pdf 

# Enable and start Bluetooth service
log "Enabling Bluetooth service..."
systemctl enable --now bluetooth.service
log "Bluetooth service has been enabled."

# Change default shell to zsh
log "Changing default shell to zsh..."
chsh -s "$(which zsh)" "$USER"

# Ask if the user wants to install AMD drivers
read -p "Do you want to install AMD drivers? (y/n): " install_amd

if [[ "$install_amd" == "y" ]]; then
	# Install necessary packages for AMD
	log "Installing AMD drivers..."
	dnf install -y xorg-x11-server-xorg xorg-x11-xinit xorg-x11-drv-amdgpu vulkan-radeon \
		lib32-vulkan-radeon radeontop

	# Create Xorg configuration if it doesn't exist
	if [ ! -f /etc/X11/xorg.conf.d/20-amdgpu.conf ]; then
		log "Creating Xorg configuration for AMD..."
		mkdir -p /etc/X11/xorg.conf.d
		tee /etc/X11/xorg.conf.d/20-amdgpu.conf >/dev/null <<EOL
Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"
EndSection
EOL
		log "Xorg configuration for AMD created at /etc/X11/xorg.conf.d/20-amdgpu.conf."
	else
		log "Xorg configuration file already exists at /etc/X11/xorg.conf.d/20-amdgpu.conf."
	fi

	# Edit GRUB configuration
	log "Editing GRUB configuration..."
	sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& quiet splash nowatchdog nvme_load=YES loglevel=3 amdgpu.dpm=1 amdgpu.audio=0 amdgpu.runpm=1 pcie_aspm=force radeon.si_support=0 radeon.cik_support=0/' /etc/default/grub

	# Update GRUB configuration
	grub2-mkconfig -o /boot/grub2/grub.cfg

	log "AMD drivers installed."
else
	log "Skipping AMD driver installation."
fi

log "Installation and setup complete on Fedora Linux."

