#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Installing Docker on Kali Linux..."

# Update package list
sudo apt update

# Install Docker
sudo apt install -y docker.io docker-compose

# Enable and start Docker service
log "Enabling and starting Docker service..."
sudo systemctl enable --now docker

# Configure permissions
log "Adding user $USER to the docker group..."
sudo usermod -aG docker "$USER"

log "Docker installation and configuration complete."
log "Please log out and log back in for group changes to take effect."
