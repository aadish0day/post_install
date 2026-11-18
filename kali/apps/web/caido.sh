#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX CAIDO WEB PROXY INSTALLER & SETUP
# Lightweight, modern Rust-based security proxy and Repeater
# Upstream: https://github.com/caido/caido | https://caido.io
# ============================================================================

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

echo "=== Installing Caido CLI on Kali Linux ==="

# 1. Detect Architecture
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
x86_64 | amd64)
    ARCH="x86_64"
    ;;
aarch64 | arm64)
    ARCH="aarch64"
    ;;
*)
    error "Unsupported architecture: $RAW_ARCH"
    exit 1
    ;;
esac
log "Detected architecture: $ARCH ($RAW_ARCH)"

# 2. Check Prerequisites
log "Checking required dependencies..."
DEPS=(curl tar jq)
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
        sudo apt-get update -qq && sudo apt-get install -y "${MISSING_DEPS[@]}"
    fi
fi

# 3. Check if available via APT first
if apt-cache show caido-cli &>/dev/null; then
    log "Caido CLI is available via Kali APT repository. Installing via package manager..."
    if command -v nala &>/dev/null; then
        sudo nala install -y caido-cli
    else
        sudo apt-get install -y caido-cli
    fi
    sudo ln -sf "$(command -v caido-cli)" "$INSTALL_DIR/caido" 2>/dev/null || true
else
    # 4. Fetch Latest CLI Release via Official Caido Release API
    log "Resolving latest CLI release link from caido.download API..."
    RELEASE_JSON=$(curl -fsSL "https://caido.download/releases/latest")
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg arch "$ARCH" '.links[] | select(.os=="linux" and .arch==$arch and .kind=="cli") | .link')
    VERSION=$(echo "$RELEASE_JSON" | jq -r '.version')

    if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
        error "Could not resolve download URL for linux-$ARCH from Caido release API."
        exit 1
    fi

    log "Target version: $VERSION"
    log "Download URL: $DOWNLOAD_URL"

    TEMP_DIR=$(mktemp -d /tmp/caido_install_XXXXXX)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    ARCHIVE_NAME="caido-cli-v${VERSION}-linux-${ARCH}.tar.gz"
    log "Downloading $ARCHIVE_NAME..."
    curl -fsSL -o "$TEMP_DIR/$ARCHIVE_NAME" "$DOWNLOAD_URL"

    log "Extracting binary..."
    tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR"

    CLI_BIN=$(find "$TEMP_DIR" -type f -name "caido-cli" | head -n 1)
    if [ -z "$CLI_BIN" ]; then
        error "Failed to locate caido-cli binary inside extracted archive."
        exit 1
    fi

    log "Installing to $INSTALL_DIR/caido-cli and $INSTALL_DIR/caido..."
    sudo install -m 0755 "$CLI_BIN" "$INSTALL_DIR/caido-cli"
    sudo ln -sf "$INSTALL_DIR/caido-cli" "$INSTALL_DIR/caido"
fi

TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

mkdir -p "$TARGET_HOME/.local/bin"
ln -sf "$INSTALL_DIR/caido-cli" "$TARGET_HOME/.local/bin/caido-cli" 2>/dev/null || true
ln -sf "$INSTALL_DIR/caido" "$TARGET_HOME/.local/bin/caido" 2>/dev/null || true

echo ""
log "Caido CLI installation complete!"
log "Commands available: 'caido' or 'caido-cli'"
log "To run: caido --listen 127.0.0.1:8080"
log "Then open your browser to: http://127.0.0.1:8080"
