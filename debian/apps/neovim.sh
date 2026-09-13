#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# NEOVIM FROM SOURCE (latest stable release)
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Installing Neovim build dependencies..."
apt_install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen npm git

if is_simulate; then
    git ls-remote --tags --exit-code https://github.com/neovim/neovim.git refs/tags/stable >/dev/null ||
        die "Neovim repository not reachable"
    log "[simulate] would build and install Neovim (stable)"
    exit 0
fi

BUILD_DIR="$(mktemp -d /tmp/neovim_build_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Cloning Neovim (stable)..."
git clone --depth 1 --branch stable https://github.com/neovim/neovim.git "$BUILD_DIR/neovim"

log "Building Neovim..."
make -C "$BUILD_DIR/neovim" CMAKE_BUILD_TYPE=Release -j"$(nproc)"

log "Installing Neovim to /usr/local..."
$SUDO make -C "$BUILD_DIR/neovim" install

log "Neovim installed: $(/usr/local/bin/nvim --version | head -n1)"
