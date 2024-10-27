#!/bin/bash

# Function to install paru
install_paru() {
    echo "Installing paru..."
    # Install necessary base-devel package group if not already installed
    if ! pacman -Qq base-devel &>/dev/null; then
        echo "Installing the base-devel package group..."
        sudo pacman -S --needed base-devel --noconfirm
    fi
    # Clone paru-bin repository
    git clone https://aur.archlinux.org/paru-bin.git
    if [ $? -ne 0 ]; then
        echo "Failed to clone paru-bin repository."
        exit 1
    fi
    # Change directory to paru-bin
    cd paru-bin || exit
    # Build and install paru without confirmation
    makepkg -si --noconfirm
    # Clean up
    cd ..
    rm -rf paru-bin
    echo "paru has been successfully installed."
}

# Check if paru is already installed
if ! command -v paru &>/dev/null; then
    install_paru
else
    echo "paru is already installed."
fi

# List of general packages to install
general_packages=(
    "thorium-browser-bin"
    "i3lock-color"
    "dracula-gtk-theme"
    "vscodium-bin"
    "moc"
    "ueberzugpp"
    "ani-cli"
    "hakuneko-desktop"
)

# List of ASUS specific packages to install
asus_packages=(
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
                fi
            fi
        fi
    done
}

echo "Installing general packages..."
install_packages "${general_packages[@]}"

# Ask if the user wants to install ASUS specific packages
read -rp "Do you want to install ASUS specific Driver ? (y/n): " install_asus
if [[ "$install_asus" == "y" ]]; then
    echo "Installing ASUS specific packages..."
    install_packages "${asus_packages[@]}"
else
    echo "Skipping ASUS specific packages."
fi

# Set thorium-browser as the default browser
echo "Setting thorium-browser as the default browser..."
unset BROWSER
xdg-settings set default-web-browser thorium-browser.desktop

# Check the current default browser
current_browser=$(xdg-settings get default-web-browser)
echo "Current default browser: $current_browser"

echo "Installation process completed!"
