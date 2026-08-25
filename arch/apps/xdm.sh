#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX XDM (XTREME DOWNLOAD MANAGER) INSTALLER
# Fetches XDM v7.2.11 directly from GitHub releases and runs the
# upstream self-extracting installer.
# ============================================================================

XDM_REPO="subhra74/xdm"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

if command -v xdman &>/dev/null || [[ -d /opt/xdman ]]; then
    log "XDM is already installed."
    exit 0
fi

# Ensure required dependencies are available
log "Installing dependencies..."
sudo pacman -S --needed --noconfirm curl tar
if ! command -v java &>/dev/null; then
    log "Java not found, installing jre-openjdk..."
    sudo pacman -S --needed --noconfirm jre-openjdk
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Fetch latest version from GitHub API
log "Fetching latest XDM version from GitHub..."
XDM_VERSION=$(curl -fsSL "https://api.github.com/repos/${XDM_REPO}/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
if [[ -z "$XDM_VERSION" ]]; then
    log "ERROR: Failed to fetch latest version from GitHub."
    exit 1
fi
XDM_URL="https://github.com/${XDM_REPO}/releases/download/${XDM_VERSION}/xdm-setup-${XDM_VERSION}.tar.xz"

log "Downloading XDM v${XDM_VERSION} from GitHub..."
curl -fSL -o "$BUILD_DIR/xdm-setup.tar.xz" "$XDM_URL"

log "Extracting archive..."
tar xf "$BUILD_DIR/xdm-setup.tar.xz" -C "$BUILD_DIR"

log "Running XDM installer..."
chmod +x "$BUILD_DIR/install.sh"
sudo "$BUILD_DIR/install.sh"

log "XDM installation complete!"
log "You can launch it from your application menu or by running 'xdman'."
