#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX PARU-BIN AUR HELPER INSTALLER (PRE-COMPILED BINARY)
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

BUILD_DIR="/tmp/paru_bin_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Fetching paru-bin (pre-compiled binary) from AUR..."
if ! git clone https://aur.archlinux.org/paru-bin.git "$BUILD_DIR" 2>/dev/null; then
    log "git clone failed, downloading paru-bin snapshot tarball from AUR..."
    curl -fsSL https://aur.archlinux.org/cgit/aur.git/snapshot/paru-bin.tar.gz | tar -xz -C "$BUILD_DIR" --strip-components=1
fi

log "Building and installing paru-bin package..."
(cd "$BUILD_DIR" && makepkg -si --noconfirm)

rm -rf "$BUILD_DIR"
log "Paru AUR helper (paru-bin) installation complete!"
