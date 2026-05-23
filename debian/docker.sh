#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Installing Docker on Debian/Ubuntu..."

# Determine the distribution name for the repo
DISTRO_ID=$(. /etc/os-release && echo "$ID")
case "$DISTRO_ID" in
    ubuntu) repo_distro="ubuntu" ;;
    *)      repo_distro="debian" ;;
esac

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL "https://download.docker.com/linux/$repo_distro/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$repo_distro \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker packages
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-model-plugin

# Enable and start Docker service
log "Enabling and starting Docker service..."
sudo systemctl enable --now docker

# Configure permissions
log "Adding user $USER to the docker group..."
sudo usermod -aG docker "$USER"

log "Docker installation and configuration complete."
log "Please log out and log back in for group changes to take effect."
