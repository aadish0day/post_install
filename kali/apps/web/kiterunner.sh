#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX KITERUNNER INSTALLER & SETUP
# Context-aware API directory fuzzer (Swagger, OpenAPI, GraphQL)
# Upstream: https://github.com/assetnote/kiterunner
# ============================================================================

REPO="assetnote/kiterunner"
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

echo "=== Installing Kiterunner API Fuzzer on Kali Linux ==="

# 1. Detect Architecture
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
x86_64 | amd64)
    ARCH="amd64"
    ;;
aarch64 | arm64)
    ARCH="arm64"
    ;;
i386 | i686)
    ARCH="386"
    ;;
*)
    error "Unsupported architecture: $RAW_ARCH"
    exit 1
    ;;
esac
log "Detected architecture: $ARCH ($RAW_ARCH)"

# 2. Check Prerequisites
log "Checking required dependencies..."
DEPS=(curl tar wget)
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

# 3. Download Kiterunner Binary
VERSION="1.0.2"
TEMP_DIR=$(mktemp -d /tmp/kiterunner_install_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_NAME="kiterunner_${VERSION}_linux_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}"

log "Downloading $ARCHIVE_NAME from GitHub..."
curl -fsSL -o "$TEMP_DIR/$ARCHIVE_NAME" "$DOWNLOAD_URL"

log "Extracting binary..."
tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR" kr

# 4. Install Binary to PATH
log "Installing kr to $INSTALL_DIR/kr..."
sudo install -m 0755 "$TEMP_DIR/kr" "$INSTALL_DIR/kr"
sudo ln -sf "$INSTALL_DIR/kr" "$INSTALL_DIR/kiterunner"

TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

mkdir -p "$TARGET_HOME/.local/bin"
ln -sf "$INSTALL_DIR/kr" "$TARGET_HOME/.local/bin/kr" 2>/dev/null || true
ln -sf "$INSTALL_DIR/kr" "$TARGET_HOME/.local/bin/kiterunner" 2>/dev/null || true

# 5. Download Assetnote Kite Wordlists
WORDLIST_DIR="${TARGET_HOME}/tool/kiterunner/wordlists"
mkdir -p "$WORDLIST_DIR"

log "Checking Assetnote API routing schemas in $WORDLIST_DIR..."
if [ ! -f "$WORDLIST_DIR/routes-large.kite" ]; then
    log "Downloading Assetnote routes-large.kite schema (compressed ~40MB)..."
    if curl -fsSL -o "$TEMP_DIR/routes-large.kite.tar.gz" "https://wordlists-cdn.assetnote.io/data/kiterunner/routes-large.kite.tar.gz"; then
        tar -xzf "$TEMP_DIR/routes-large.kite.tar.gz" -C "$WORDLIST_DIR"
        log "Extracted routes-large.kite successfully."
    else
        warn "Could not download routes-large.kite automatically. You can download manually later."
    fi
else
    log "Wordlist routes-large.kite already present."
fi

# Set permissions
sudo chown -R "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/tool/kiterunner" 2>/dev/null || true

echo ""
log "Kiterunner installation complete!"
log "Installed commands: 'kr' and 'kiterunner'"
log "Wordlist path: $WORDLIST_DIR/routes-large.kite"
log "Example scan: kr scan https://target.com/api -w $WORDLIST_DIR/routes-large.kite -x 20"
