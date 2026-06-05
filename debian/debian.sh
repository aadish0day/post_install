#!/usr/bin/env bash
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep sudo alive during long operations
if sudo -v; then
    sudo -n true
    keep_sudo_alive() { while true; do
        sleep 60
        sudo -n true
    done; }
    keep_sudo_alive &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill ${SUDO_KEEP_ALIVE_PID} 2>/dev/null || true' EXIT
fi

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to install packages if not already installed
install_if_needed() {
    local pkg
    local failures=()
    local to_install=()

    for pkg in "$@"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            to_install+=("$pkg")
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
        if ! sudo nala install -y "${to_install[@]}"; then
            echo "Some packages failed to install, checking..."
            for pkg in "${to_install[@]}"; do
                if ! dpkg -l | grep -q "^ii  $pkg "; then
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

# ============================================================================
# SYSTEM UPDATE
# ============================================================================

# Ensure nala is installed
echo "Ensuring nala is installed..."
sudo apt update && sudo apt install -y nala

# Update the system
echo "Updating the system..."
sudo nala update && sudo nala upgrade -y

# ============================================================================
# PACKAGE LISTS
# ============================================================================

# List of general packages
packages=(
    ranger ncdu mpv maven yt-dlp htop fzf git git-lfs unzip nodejs
    flameshot xclip ueberzug highlight atool mediainfo
    android-tools-adb android-tools-fastboot img2pdf
    zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb
    obs-studio picom nitrogen xss-lock qalculate-gtk libreoffice
    bluez bat alacritty jpegoptim zip tar p7zip zstd lz4 xz-utils
    trash-cli lxrandr python3-pip
)

# ============================================================================
# INSTALLATION
# ============================================================================

echo ""
echo "Installing packages..."
install_if_needed "${packages[@]}"

# Initialize Git LFS for the current user
if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
    echo "Initializing Git LFS..."
    git lfs install --skip-repo
fi

# Install Starship if not already installed
if ! command -v starship &>/dev/null; then
    echo "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh
else
    echo "Starship is already installed."
fi

# Ask about Docker
echo ""
read -rp "Do you want to install Docker? (y/n): " install_docker_input
if [[ $install_docker_input =~ ^[Yy]$ ]]; then
    echo "Installing Docker..."
    if [ -f "$SCRIPT_DIR/docker.sh" ]; then
        bash "$SCRIPT_DIR/docker.sh"
    else
        echo "Error: docker.sh not found."
    fi
fi

# Ask about Pacstall
echo ""
read -rp "Do you want to install Pacstall (AUR-like package manager for Debian)? (y/n): " install_pacstall_input
if [[ $install_pacstall_input =~ ^[Yy]$ ]]; then
    echo "Installing Pacstall..."
    sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)"

    echo ""
    echo "Installing Pacstall packages..."
    for pkg in ani-cli-bin appimagelauncher-deb; do
        if pacstall -I "$pkg" -P; then
            echo "$pkg installed successfully."
        else
            echo "Failed to install $pkg"
        fi
    done
fi

echo ""
echo "=========================================="
echo "Installation completed successfully!"
echo "=========================================="
