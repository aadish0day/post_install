#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX LAZYDOCKER INSTALLER (CLI / TUI)
# Terminal UI for Docker and Docker-Compose
# ============================================================================

REPO="jesseduffield/lazydocker"
INSTALL_DIR="/usr/local/bin"

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

echo "=== Installing Lazydocker CLI on Kali Linux ==="

# 1. Check & Install Dependencies
log "Checking required dependencies..."
DEPS=(curl tar grep sed)
MISSING_DEPS=()
for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log "Installing missing dependencies: ${MISSING_DEPS[*]}..."
    if command -v nala &>/dev/null; then
        sudo nala install -y "${MISSING_DEPS[@]}"
    else
        sudo apt update -qq && sudo apt install -y "${MISSING_DEPS[@]}"
    fi
fi

# 2. Detect Architecture
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
    x86_64|amd64)
        ARCH="x86_64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    armv7*|armhf)
        ARCH="armv7"
        ;;
    armv6*)
        ARCH="armv6"
        ;;
    i386|i686)
        ARCH="x86"
        ;;
    *)
        error "Unsupported architecture: $RAW_ARCH"
        exit 1
        ;;
esac
log "Detected architecture: $ARCH ($RAW_ARCH)"

# 3. Detect Latest Version
log "Fetching latest lazydocker release version from GitHub..."
TAG=$(curl -sSL -H 'Accept: application/json' "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || true)

if [[ -z "$TAG" ]]; then
    # Fallback to redirect resolution if API rate-limited
    TAG=$(curl -fsSLI -o /dev/null -w "%{url_effective}" "https://github.com/${REPO}/releases/latest" 2>/dev/null | grep -oP '[^/]+$' || true)
fi

if [[ -z "$TAG" ]]; then
    # Hardcoded fallback if offline / completely blocked
    TAG="v0.24.1"
    warn "Could not resolve latest tag from GitHub API, falling back to $TAG"
fi

VERSION="${TAG#v}"
log "Target version: $TAG"

# 4. Download and Extract Binary
TEMP_DIR=$(mktemp -d /tmp/lazydocker_install_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_NAME="lazydocker_${VERSION}_Linux_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE_NAME}"

log "Downloading $ARCHIVE_NAME..."
if ! curl -fSL -o "$TEMP_DIR/$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
    warn "Direct download failed, falling back to official upstream install script..."
    DIR="$TEMP_DIR" curl -s https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
fi

if [ -f "$TEMP_DIR/$ARCHIVE_NAME" ]; then
    log "Extracting binary..."
    tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR" lazydocker
fi

if [ ! -f "$TEMP_DIR/lazydocker" ]; then
    error "Failed to extract lazydocker binary."
    exit 1
fi

# 5. Install Binary to PATH
log "Installing lazydocker to $INSTALL_DIR/lazydocker..."
sudo install -m 0755 "$TEMP_DIR/lazydocker" "$INSTALL_DIR/lazydocker"

mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_DIR/lazydocker" "$HOME/.local/bin/lazydocker"

# 6. Configure Shell Aliases
log "Setting up shell alias (lzd -> lazydocker)..."
for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rcfile" ]; then
        if ! grep -q "alias lzd=" "$rcfile"; then
            echo "" >> "$rcfile"
            echo "# Lazydocker CLI alias" >> "$rcfile"
            echo "alias lzd='lazydocker'" >> "$rcfile"
            log "Added 'lzd' alias to $rcfile"
        fi
    fi
done

# 7. Check Docker Setup & Permissions
echo ""
if ! command -v docker &>/dev/null; then
    warn "Docker is not installed on this system!"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/docker.sh" ]; then
        read -rp "Would you like to install Docker now using kali/apps/docker.sh? (y/n): " install_docker_choice
        if [[ $install_docker_choice =~ ^[Yy]$ ]]; then
            bash "$SCRIPT_DIR/docker.sh"
        fi
    else
        warn "Please install Docker to use lazydocker: sudo apt install docker.io"
    fi
else
    # Check if docker daemon is running
    if ! systemctl is-active --quiet docker; then
        warn "Docker service is not running. Starting Docker service..."
        sudo systemctl enable --now docker || true
    fi

    # Check docker group membership
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        log "Adding user $USER to docker group..."
        sudo usermod -aG docker "$USER"
        warn "You were added to the docker group. Please log out and back in (or run 'newgrp docker') for permissions to take effect."
    fi
fi

echo ""
log "Lazydocker CLI installation complete!"
log "Installed version: $(lazydocker --version 2>/dev/null || echo "$TAG")"
log "Run it in your terminal with: lazydocker  (or alias: lzd)"
