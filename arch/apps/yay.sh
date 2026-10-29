#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX YAY-BIN AUR HELPER INSTALLER (PRE-COMPILED BINARY)
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

BUILD_DIR="/tmp/yay_bin_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Fetching yay-bin (pre-compiled binary) from AUR..."
if ! git clone https://aur.archlinux.org/yay-bin.git "$BUILD_DIR" 2>/dev/null; then
    log "git clone failed, downloading yay-bin snapshot tarball from AUR..."
    curl -fsSL https://aur.archlinux.org/cgit/aur.git/snapshot/yay-bin.tar.gz | tar -xz -C "$BUILD_DIR" --strip-components=1
fi

log "Building and installing yay-bin package..."
(cd "$BUILD_DIR" && makepkg -si --noconfirm)

rm -rf "$BUILD_DIR"
log "Yay AUR helper (yay-bin) installation complete!"
