#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Installing Docker on Arch Linux..."

# Install Docker, Docker Compose, and Buildx
sudo pacman -S --needed docker docker-compose docker-buildx --noconfirm --overwrite '*'

# Enable and start Docker socket for on-demand activation
log "Enabling and starting Docker socket (on-demand activation)..."
sudo systemctl disable docker.service 2>/dev/null || true
sudo systemctl enable --now docker.socket

# Configure permissions
log "Adding user $USER to the docker group..."
sudo usermod -aG docker "$USER"

log "Docker installation and configuration complete."
log "Please log out and log back in for group changes to take effect."
