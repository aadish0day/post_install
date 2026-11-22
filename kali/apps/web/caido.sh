#!/usr/bin/env bash
set -euo pipefail

# Caido CLI: lightweight web security proxy (https://caido.io)
# Kali ships caido-cli in its repos: that is the supported, signed path.
# The direct-download fallback has no published checksum and is opt-in only.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
INSTALL_DIR="/usr/local/bin"

echo "=== Installing Caido CLI on Kali Linux ==="

if apt_has_candidate caido-cli; then
    apt_install caido-cli
    if ! command -v caido &>/dev/null && command -v caido-cli &>/dev/null; then
        sudo ln -sf "$(command -v caido-cli)" "$INSTALL_DIR/caido"
    fi
else
    if [ "${CAIDO_ALLOW_UNVERIFIED:-0}" != 1 ]; then
        error "caido-cli is not available from your apt repositories (is this Kali?)."
        error "Refusing to download an unverified binary. Set CAIDO_ALLOW_UNVERIFIED=1 to override."
        exit 1
    fi

    case "$(uname -m)" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="aarch64" ;;
    *)
        error "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
    esac
    apt_install curl tar jq

    warn "Downloading Caido CLI without checksum verification (CAIDO_ALLOW_UNVERIFIED=1)."
    RELEASE_JSON="$(curl -fsSL "https://caido.download/releases/latest")" || {
        error "Could not reach caido.download."
        exit 1
    }
    DOWNLOAD_URL="$(echo "$RELEASE_JSON" | jq -r --arg arch "$ARCH" '.links[] | select(.os=="linux" and .arch==$arch and .kind=="cli") | .link')"
    if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
        error "Could not resolve a download URL for linux-$ARCH."
        exit 1
    fi

    TEMP_DIR="$(mktemp -d /tmp/caido_install_XXXXXX)"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    curl -fsSL -o "$TEMP_DIR/caido.tar.gz" "$DOWNLOAD_URL"
    tar -xzf "$TEMP_DIR/caido.tar.gz" -C "$TEMP_DIR"
    CLI_BIN="$(find "$TEMP_DIR" -type f -name 'caido-cli' | head -n 1)"
    [ -n "$CLI_BIN" ] || {
        error "caido-cli binary not found in archive."
        exit 1
    }
    sudo install -m 0755 "$CLI_BIN" "$INSTALL_DIR/caido-cli"
    sudo ln -sf "$INSTALL_DIR/caido-cli" "$INSTALL_DIR/caido"
fi

log "Caido CLI installation complete! Run: caido-cli --listen 127.0.0.1:8080  then open http://127.0.0.1:8080"
