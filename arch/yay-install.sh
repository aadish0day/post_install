#!/bin/bash

# Function to install yay
install_yay() {
    echo "yay could not be found, installing..."
    
    # Install necessary base-devel package group if not already installed
    if ! pacman -Qq base-devel &> /dev/null; then
        echo "Installing the base-devel package group..."
        sudo pacman -S --needed base-devel
    fi

    # Clone yay repository
    git clone https://aur.archlinux.org/yay.git
    if [ $? -ne 0 ]; then
        echo "Failed to clone yay repository."
        exit 1
    fi

    # Change directory to yay
    cd yay || exit

    # Build and install yay
    makepkg -si

    # Clean up
    cd ..
    rm -rf yay

    echo "yay has been successfully installed."
}

# Function to check and install a package if it's not installed
install_package_if_missing() {
    local package_name=$1
    # Checking if the package is already installed
    if ! yay -Qi "$package_name" &> /dev/null && ! pacman -Qi "$package_name" &> /dev/null; then
        echo "Installing $package_name..."
        yay -S --noconfirm "$package_name"
    else
        echo "$package_name is already installed."
    fi
}

# Check if yay is installed, install it if not
if ! command -v yay &> /dev/null; then
    install_yay
else
    echo "yay is already installed."
fi

# Update system and databases
echo "Updating system and databases..."
yay -Syu --noconfirm

# List of packages to install
packages=(
    i3lock-color
    thorium-browser-bin
    vscodium-bin
    github-desktop-bin
    moc
    ani-cli
    hakuneko-desktop
)

# Loop through the list and install if missing
for package in "${packages[@]}"; do
    install_package_if_missing "$package"
done

echo "Installation process completed!"

