#!/bin/bash

# Set strict error handling
set -eo pipefail

# Function to log script actions
log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
	log "This script must be run as root"
	exit 1
fi

# Backup the existing dnf.conf and replace it with a new one
log "Backing up and replacing dnf.conf..."
cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
cp ./dnf.conf /etc/dnf/dnf.conf

# Update the system
log "Updating the system..."
dnf update -y

# Install RPM Fusion repositories
log "Installing RPM Fusion repositories..."
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
	"https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Swapping ffmpeg-free for ffmpeg
log "Swapping ffmpeg-free for ffmpeg..."
dnf swap -y ffmpeg-free ffmpeg --allowerasing

# Perform group updates
log "Performing group updates..."
dnf groupupdate -y core
dnf groupupdate -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupupdate -y sound-and-video

# Install essential packages
log "Installing essential packages..."
dnf install -y ranger ncdu mpv neovim maven yt-dlp fzf git unzip nodejs flameshot htop npm xclip highlight atool mediainfo fastfetch android-tools zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock qalculate-qt brightnessctl bluez blueman bat alacritty jpegoptim zip unzip tar p7zip zstd lz4 xz

# Install Python utilities with pip
log "Installing Python utilities with pip..."
dnf install -y python3-pip
pip3 install img2pdf ueberzug

# Enable COPR repository for starship and install it
log "Enabling COPR repository for starship and installing it..."
dnf install -y dnf-plugins-core
dnf copr enable atim/starship -y
dnf install -y starship

# Install LibreOffice
log "Installing LibreOffice..."
dnf install -y libreoffice

log "Installation and setup complete on Fedora Linux."
