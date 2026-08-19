#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX YAY AUR HELPER INSTALLER
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

if command -v yay &>/dev/null; then
    log "Yay AUR helper is already installed ($(yay --version 2>/dev/null | head -n1 || echo 'active'))."
    exit 0
fi

log "Installing prerequisites (base-devel, git)..."
sudo pacman -S --needed --noconfirm base-devel git

BUILD_DIR="/tmp/yay_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Cloning yay-bin from AUR..."
if git clone https://aur.archlinux.org/yay-bin.git "$BUILD_DIR" 2>/dev/null; then
    log "Building and installing yay-bin..."
    (cd "$BUILD_DIR" && makepkg -si --noconfirm)
else
    log "yay-bin clone failed, falling back to compiling yay from source..."
    rm -rf "$BUILD_DIR"
    sudo pacman -S --needed --noconfirm go
    git clone https://aur.archlinux.org/yay.git "$BUILD_DIR"
    (cd "$BUILD_DIR" && makepkg -si --noconfirm)
fi

rm -rf "$BUILD_DIR"
log "Yay AUR helper installation complete!"
