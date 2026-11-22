#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Docker on Kali Linux ==="

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources.
# Kali is rolling (/etc/debian_version just says "kali-rolling"), so probe which Debian
# suite Docker publishes for: newest first. Override with DOCKER_DEBIAN_CODENAME.
DEBIAN_CODENAME="${DOCKER_DEBIAN_CODENAME:-}"
if [ -z "$DEBIAN_CODENAME" ]; then
    for c in trixie bookworm; do
        if curl -fsI "https://download.docker.com/linux/debian/dists/$c/Release" >/dev/null 2>&1; then
            DEBIAN_CODENAME="$c"
            break
        fi
    done
    DEBIAN_CODENAME="${DEBIAN_CODENAME:-bookworm}"
fi
echo "Using Docker apt suite: $DEBIAN_CODENAME"

if dpkg -s docker.io &>/dev/null; then
    echo "NOTE: Kali's docker.io is installed; docker-ce conflicts with it and apt will replace it."
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $DEBIAN_CODENAME stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update

# Install Docker packages
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

# Enable and start Docker service
echo "Enabling and starting Docker service..."
sudo systemctl enable --now docker

# Configure permissions
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
echo "Adding user $TARGET_USER to the docker group..."
sudo usermod -aG docker "$TARGET_USER"

echo "Docker installation and configuration complete!"
echo "Please log out and log back in for group changes to take effect."
