#!/bin/bash

# Exit on any error
set -e

# Backup the existing dnf.conf and replace it with a new one
echo "Backing up and replacing dnf.conf..."
sudo mv /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
sudo cp ./dnf.conf /etc/dnf/dnf.conf

# Update the system
echo "Updating the system..."
sudo dnf update -y

# Install RPM Fusion repositories
echo "Installing RPM Fusion repositories..."
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Perform group updates
echo "Performing group updates..."
sudo dnf groupupdate -y core
sudo dnf groupupdate -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf groupupdate -y sound-and-video

# Install packages
echo "Installing packages..."
sudo dnf install -y ranger ncdu mpv neovim maven yt-dlp fzf git unzip nodejs flameshot htop npm
echo "Installation and setup complete on fedora Linux."
