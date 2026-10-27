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

if [ -x /usr/bin/advcp ] && [ -x /usr/bin/advmv ]; then
    log "advcpmv binaries are already installed in /usr/bin."
else
    if is_simulate; then
        log "[simulate] would install dependencies and compile advcpmv from upstream"
    else
        log "Installing dependencies for advcpmv..."
        apt_install build-essential patch curl xz-utils texinfo

        BUILD_DIR="$(mktemp -d /tmp/advcpmv_build_XXXXXX)"
        trap 'rm -rf "$BUILD_DIR"' EXIT

        log "Downloading upstream advcpmv installer..."
        curl -fsSL https://raw.githubusercontent.com/jarun/advcpmv/master/install.sh -o "$BUILD_DIR/install.sh"

        log "Patching installer for parallel compilation and doc bypass..."
        # shellcheck disable=SC2016
        sed -i 's/^[[:space:]]*make[[:space:]]*$/    touch doc\/*.info 2>\/dev\/null || true\n    make -j$(nproc) src\/cp src\/mv || make -j$(nproc)/' "$BUILD_DIR/install.sh"

        log "Building advcpmv..."
        (cd "$BUILD_DIR" && sh install.sh)

        log "Installing binaries to /usr/bin..."
        $SUDO install -m 0755 "$BUILD_DIR/advcp" /usr/bin/advcp
        $SUDO install -m 0755 "$BUILD_DIR/advmv" /usr/bin/advmv

        log "Creating symlinks (cpg, mvg)..."
        $SUDO ln -sf /usr/bin/advcp /usr/bin/cpg
        $SUDO ln -sf /usr/bin/advmv /usr/bin/mvg
        $SUDO ln -sf /usr/bin/advcp /usr/local/bin/advcp 2>/dev/null || true
        $SUDO ln -sf /usr/bin/advmv /usr/local/bin/advmv 2>/dev/null || true
    fi
fi

if ! is_simulate; then
    ADVCP_BIN="/usr/bin/advcp"
    ADVMV_BIN="/usr/bin/advmv"

    log "Configuring shell aliases..."
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ]; then
            append_line_once "$rcfile" "alias cp='$ADVCP_BIN -g'"
            append_line_once "$rcfile" "alias mv='$ADVMV_BIN -g'"
        fi
    done
fi

log "advcpmv installation complete."
