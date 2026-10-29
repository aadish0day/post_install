#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# XDM (XTREME DOWNLOAD MANAGER)
# Runs the upstream installer from the latest GitHub release.
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v xdman >/dev/null 2>&1 || command -v xdm-app >/dev/null 2>&1 || [ -d /opt/xdman ]; then
    log "XDM is already installed."
    exit 0
fi

log "Installing dependencies..."
apt_install curl

url="$(github_asset_url subhra74/xdm 'xdm-app_.*_amd64\.deb$')" || true
[ -n "${url:-}" ] || die "Could not resolve the latest XDM release."

if is_simulate; then
    url_ok "$url" >/dev/null && log "[simulate] would install XDM from $url"
    exit 0
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Downloading $url..."
download "$url" "$BUILD_DIR/xdm-app.deb"
$SUDO dpkg -i "$BUILD_DIR/xdm-app.deb" || true
$SUDO apt-get install -f -y

log "XDM installation complete."
