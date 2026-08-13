#!/usr/bin/env bash

# Set strict error handling
set -eo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure the script is run as root (auto-elevate if needed)
if [ "$(id -u)" != "0" ]; then
    log "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

log "Starting Fedora setup..."

# Safely optimize DNF / DNF5 configuration non-destructively
log "Optimizing DNF configuration..."
for config_target in /etc/dnf/dnf.conf /etc/dnf/dnf5.conf; do
    if [ -f "$config_target" ]; then
        if [ ! -f "${config_target}.bak" ]; then
            cp "$config_target" "${config_target}.bak"
        fi
        
        # Ensure setting keys exist or update them without wiping the whole file
        declare -A dnf_opts=(
            ["fastestmirror"]="True"
            ["max_parallel_downloads"]="10"
            ["defaultyes"]="True"
            ["countme"]="False"
            ["installonly_limit"]="3"
            ["clean_requirements_on_remove"]="True"
        )
        for key in "${!dnf_opts[@]}"; do
            val="${dnf_opts[$key]}"
            if grep -q "^${key}=" "$config_target"; then
                sed -i "s|^${key}=.*|${key}=${val}|" "$config_target"
            else
                echo "${key}=${val}" >> "$config_target"
            fi
        done
    fi
done

# Update the system
log "Updating the system..."
dnf update -y

# Install RPM Fusion repositories
log "Installing RPM Fusion repositories..."
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Enable COPR and install starship
log "Enabling COPR for starship..."
dnf copr enable atim/starship -y
sudo dnf copr enable tokariew/i3lock-color

# Install essential packages
log "Installing essential packages..."
dnf install -y neovim ranger ncdu mpv maven yt-dlp fzf git git-lfs nodejs gcc make ripgrep fd-find unzip htop gettext libtool \
    doxygen flameshot npm xclip highlight atool mediainfo fastfetch android-tools zathura zathura-pdf-mupdf \
    zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen xss-lock qalculate-qt libreoffice brightnessctl \
    qbittorrent bluez blueman bat alacritty zsh jpegoptim zip tar p7zip zstd lz4 xz trash-cli lxrandr wine winetricks \
    gamemode lutris papirus-icon-theme tree starship i3lock-color

# Install Python utilities with pip
log "Installing Python utilities with pip..."
dnf install -y python3-pip
python3 -m pip install -U --break-system-packages gallery-dl

# Initialize Git LFS for the current user
if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
    log "Initializing Git LFS..."
    git lfs install --skip-repo
fi

# Enable and start Bluetooth service
log "Enabling Bluetooth service..."
systemctl enable --now bluetooth.service
log "Bluetooth service has been enabled."

# Change default shell to zsh
log "Changing default shell to zsh..."
chsh -s "$(which zsh)" "$USER"

# Ask about Docker
echo ""
read -rp "Do you want to install Docker? (y/n): " install_docker_input
if [[ $install_docker_input =~ ^[Yy]$ ]]; then
    log "Installing Docker..."
    if [ -f "$SCRIPT_DIR/apps/docker.sh" ]; then
        bash "$SCRIPT_DIR/apps/docker.sh"
    else
        log "Error: apps/docker.sh not found."
    fi
fi
