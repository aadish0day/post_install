#!/usr/bin/env bash
set -euo pipefail

# Update system and packages
sudo pacman -Sy --noconfirm

# Install reflector for managing mirror list
sudo pacman -S --needed reflector --noconfirm

# Prompt user to configure mirrors
read -p "Do you want to configure the mirror list for India using reflector? (y/n): " configure_mirrors
if [[ $configure_mirrors =~ ^[Yy]$ ]]; then
    sudo reflector --latest 5 --country India --protocol https --sort rate --save /etc/pacman.d/mirrorlist
else
    echo "Skipping mirror configuration."
fi

# Update system and packages
sudo pacman -Syu --noconfirm

install_if_needed() {
    local pkg
    local failures=()
    local to_install=()

    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
        if ! sudo pacman -S --noconfirm "${to_install[@]}"; then
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

# List of general packages to install
packages=(
    neovim ranger ncdu mpv maven yt-dlp fzf git nodejs gcc make ripgrep fd unzip htop gettext libtool doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools img2pdf zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock qalculate-qt libreoffice-still brightnessctl qbittorrent bluez bluez-utils blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr mkinitcpio ttf-fira-mono papirus-icon-theme tree otf-firamono-nerd zoxide xdg-desktop-portal xdg-desktop-portal-gtk zed
)

# List of gaming packages to install
gaming_packages=(
    lutris wine wine-gecko wine-mono winetricks gamemode lib32-gamemode
    giflib lib32-giflib gnutls lib32-gnutls v4l-utils lib32-v4l-utils libpulse
    lib32-libpulse alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib
    sqlite lib32-sqlite libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd
    libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs
    vulkan-icd-loader lib32-vulkan-icd-loader sdl2 lib32-sdl2
)

# Function to install gaming packages
install_gaming_packages() {
    echo "Installing gaming packages..."
    install_if_needed "${gaming_packages[@]}"
}

# Ensure unique packages and call install_if_needed for general packages
declare -A unique_packages
for pkg in "${packages[@]}"; do
    unique_packages["$pkg"]=1
done
install_if_needed "${!unique_packages[@]}"

# Prompt user for gaming installation
read -p "Do you want to install gaming packages? (y/n): " install_gaming
if [[ $install_gaming =~ ^[Yy]$ ]]; then
    install_gaming_packages
fi

# Prompt user for ASUS-specific applications installation
read -p "Do you want to install ASUS-specific applications (asusctl, supergfxctl, rog-control-center)? (y/n): " install_asus
if [[ $install_asus =~ ^[Yy]$ ]]; then
    # Set up the repository key and add the g14 repo to pacman.conf
    echo "Adding ASUS Linux repository and installing ASUS-specific applications..."

    sudo pacman-key --recv-keys 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35
    sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35
    sudo pacman-key --lsign-key 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35

    # Verify key again to ensure it's signed correctly
    sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35

    if ! grep -q "\[g14\]" /etc/pacman.conf; then
        echo -e "\n[g14]\nServer = https://arch.asus-linux.org" | sudo tee -a /etc/pacman.conf
    fi

    sudo pacman -Syu --noconfirm
    install_if_needed asusctl supergfxctl rog-control-center

    # Enable related services
    sudo systemctl enable power-profiles-daemon.service
    sudo systemctl enable supergfxd
    sudo systemctl enable switcheroo-control
fi

# Restart xdg-desktop-portal services
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk

# Enable Bluetooth and display message
sudo systemctl enable bluetooth.service
echo "Bluetooth service has been enabled."

# Change default shell to zsh
chsh -s "$(which zsh)" "$USER"
