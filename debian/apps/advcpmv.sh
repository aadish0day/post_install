#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ADVCPMV (Advanced Copy & Move)
# Coreutils cp and mv patched with progress bars.
# Compiles and installs advcp and advmv from upstream source.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

if command -v advcp >/dev/null 2>&1 && command -v advmv >/dev/null 2>&1; then
    log "advcpmv is already installed."
    exit 0
fi

if is_simulate; then
    log "[simulate] would install dependencies and compile advcpmv from upstream"
    exit 0
fi

log "Installing dependencies for advcpmv..."
apt_install build-essential patch curl xz-utils

BUILD_DIR="$(mktemp -d /tmp/advcpmv_build_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Downloading upstream advcpmv installer..."
curl -fsSL https://raw.githubusercontent.com/jarun/advcpmv/master/install.sh -o "$BUILD_DIR/install.sh"

log "Patching installer for parallel compilation..."
# shellcheck disable=SC2016
sed -i 's/^[[:space:]]*make[[:space:]]*$/    make -j$(nproc)/' "$BUILD_DIR/install.sh"

log "Building advcpmv..."
(cd "$BUILD_DIR" && sh install.sh)

log "Installing binaries to /usr/local/bin..."
$SUDO install -m 0755 "$BUILD_DIR/advcp" /usr/local/bin/advcp
$SUDO install -m 0755 "$BUILD_DIR/advmv" /usr/local/bin/advmv

log "Creating symlinks (cpg, mvg)..."
$SUDO ln -sf /usr/local/bin/advcp /usr/local/bin/cpg
$SUDO ln -sf /usr/local/bin/advmv /usr/local/bin/mvg

log "Configuring shell aliases..."
for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rcfile" ]; then
        append_line_once "$rcfile" "alias cp='/usr/local/bin/advcp -g'"
        append_line_once "$rcfile" "alias mv='/usr/local/bin/advmv -g'"
    fi
done

log "advcpmv installation complete."
