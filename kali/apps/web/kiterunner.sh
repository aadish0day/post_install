#!/usr/bin/env bash
set -euo pipefail

# Kiterunner: contextual API/content discovery (https://github.com/assetnote/kiterunner)
# Pinned release with hardcoded sha256 per architecture.
# NOTE: upstream has been unmaintained since 2021.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init

REPO="assetnote/kiterunner"
VERSION="1.0.2"
INSTALL_DIR="/usr/local/bin"

echo "=== Installing Kiterunner API Fuzzer on Kali Linux ==="

case "$(uname -m)" in
x86_64 | amd64)
    ARCH="amd64"
    SHA256="6f0b70aabf747de592445a690281897eebbc45927e9264185d34ffb11637613b"
    ;;
aarch64 | arm64)
    ARCH="arm64"
    SHA256="ec763297e1a9da49c06fc7853418e5839b03b2326204e7d2dde592f521eddd28"
    ;;
i386 | i686)
    ARCH="386"
    SHA256="bf29b4ed3da7b520937d212dfbc5bb7db8d88944851ec432a36c833b47caf69b"
    ;;
*)
    error "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

apt_install curl tar

TEMP_DIR="$(mktemp -d /tmp/kiterunner_install_XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_NAME="kiterunner_${VERSION}_linux_${ARCH}.tar.gz"
log "Downloading $ARCHIVE_NAME..."
curl -fsSL -o "$TEMP_DIR/$ARCHIVE_NAME" "https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}"
verify_sha256 "$TEMP_DIR/$ARCHIVE_NAME" "$SHA256"

tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR" kr
sudo install -m 0755 "$TEMP_DIR/kr" "$INSTALL_DIR/kr"
sudo ln -sf "$INSTALL_DIR/kr" "$INSTALL_DIR/kiterunner"

# Wordlists live with the other tools, owned by the user
WORDLIST_DIR="$TOOL_BASE/kiterunner/wordlists"
run_as_target mkdir -p "$WORDLIST_DIR"
if [ ! -f "$WORDLIST_DIR/routes-large.kite" ]; then
    log "Downloading Assetnote routes-large.kite schema (~40MB; no upstream checksum is published)..."
    if curl -fsSL -o "$TEMP_DIR/routes-large.kite.tar.gz" "https://wordlists-cdn.assetnote.io/data/kiterunner/routes-large.kite.tar.gz"; then
        tar -xzf "$TEMP_DIR/routes-large.kite.tar.gz" -C "$TEMP_DIR"
        found="$(find "$TEMP_DIR" -name 'routes-large.kite' -type f | head -n1)"
        if [ -n "$found" ]; then
            run_as_target install -m 0644 "$found" "$WORDLIST_DIR/routes-large.kite"
            log "Extracted routes-large.kite."
        else
            warn "routes-large.kite not found in archive."
        fi
    else
        warn "Could not download routes-large.kite automatically; download it manually later."
    fi
fi

log "Kiterunner installation complete! Commands: kr, kiterunner"
log "Example: kr scan https://target.com/api -w $WORDLIST_DIR/routes-large.kite -x 20"
