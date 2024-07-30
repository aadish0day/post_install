#!/usr/bin/env bash
set -euo pipefail

echo "Arch Linux setup..."

# Update system and packages
sudo pacman -Syu --noconfirm

# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm

# Configure mirrors for India using reflector
sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Update system and packages again after setting mirrors
sudo pacman -Syu --noconfirm

install_if_needed() {
    local pkg
    local failures=()
    local to_install=()

    for pkg in "$@"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
        if ! sudo pacman -S "${to_install[@]}" --noconfirm; then
            echo "Some packages failed to install, checking..."
            for pkg in "${to_install[@]}"; do
                if ! pacman -Q "$pkg" &>/dev/null; then
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

# List of packages to install
packages=(neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr wine wine-gecko wine-mono winetricks gamemode lib32-gamemode lutris mkinitcpio)

# Ensure unique packages and call install_if_needed
packages=($(printf "%s\n" "${packages[@]}" | sort -u))
install_if_needed "${packages[@]}"

# Enable Bluetooth and display message
sudo systemctl enable --now bluetooth.service
echo "Bluetooth service has been enabled."

# Change default shell to zsh
chsh -s "$(which zsh)" "$USER"

echo "Installation and setup complete on Arch Linux."

