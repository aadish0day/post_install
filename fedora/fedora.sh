#!/bin/bash

# Exit on any error
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

# Backup the existing dnf.conf and replace it with a new one
echo "Backing up and replacing dnf.conf..."
cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
cp ./dnf.conf /etc/dnf/dnf.conf

# Update the system
echo "Updating the system..."
dnf update -y

# Install RPM Fusion repositories
echo "Installing RPM Fusion repositories..."
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Corrected: Perform the swap operation after adding the RPM Fusion repos
echo "Swapping ffmpeg-free for ffmpeg..."
dnf swap -y ffmpeg-free ffmpeg --allowerasing

# Perform group updates
echo "Performing group updates..."
dnf groupupdate -y core
dnf groupupdate -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupupdate -y sound-and-video

# Install packages
echo "Installing packages..."
dnf install -y ranger ncdu mpv neovim maven yt-dlp fzf git unzip nodejs flameshot htop npm xclip highlight atool mediainfo fastfetch android-tools zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock qalculate-qt brightnessctl bluez blueman bat alacritty jpegoptim zip unzip tar p7zip zstd lz4 xz

# Install ueberzug and img2pdf using pip
echo "Installing ueberzug and img2pdf using pip..."
dnf install -y python3-pip
pip3 install img2pdf

# Enable COPR repository for starship and install it
echo "Enabling COPR repository for starship and installing it..."
dnf install -y dnf-plugins-core
dnf copr enable atim/starship -y
dnf install -y starship

# Install LibreOffice (Fedora provides a single version, no need for libreoffice-still)
echo "Installing LibreOffice..."
dnf install -y libreoffice

echo "Installation and setup complete on Fedora Linux."
