#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# XDM (XTREME DOWNLOAD MANAGER)
# Runs the upstream installer from the latest GitHub release.
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v xdman >/dev/null 2>&1 || [ -d /opt/xdman ]; then
    log "XDM is already installed."
    exit 0
fi

log "Installing dependencies..."
apt_install curl tar xz-utils default-jre

url="$(github_asset_url subhra74/xdm 'xdm-setup-.*\.tar\.xz$')" || true
[ -n "${url:-}" ] || die "Could not resolve the latest XDM release."

if is_simulate; then
    url_ok "$url" >/dev/null && log "[simulate] would install XDM from $url"
    exit 0
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Downloading $url..."
download "$url" "$BUILD_DIR/xdm-setup.tar.xz"
tar -xf "$BUILD_DIR/xdm-setup.tar.xz" -C "$BUILD_DIR"
chmod +x "$BUILD_DIR/install.sh"
$SUDO "$BUILD_DIR/install.sh"

log "XDM installation complete. Launch it with 'xdman'."
