#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX PARU AUR HELPER INSTALLER
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

if command -v paru &>/dev/null; then
    log "Paru AUR helper is already installed ($(paru --version 2>/dev/null | head -n1 || echo 'active'))."
    exit 0
fi

log "Installing prerequisites (base-devel, git)..."
sudo pacman -S --needed --noconfirm base-devel git

BUILD_DIR="/tmp/paru_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Cloning paru-bin from AUR..."
if git clone https://aur.archlinux.org/paru-bin.git "$BUILD_DIR"; then
    log "Building and installing paru-bin..."
    (cd "$BUILD_DIR" && makepkg -si --noconfirm)
else
    log "Falling back to compiling paru from source..."
    rm -rf "$BUILD_DIR"
    git clone https://aur.archlinux.org/paru.git "$BUILD_DIR"
    (cd "$BUILD_DIR" && makepkg -si --noconfirm)
fi

rm -rf "$BUILD_DIR"
log "Paru AUR helper installation complete!"
