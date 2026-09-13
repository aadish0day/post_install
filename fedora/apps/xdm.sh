#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA XDM (XTREME DOWNLOAD MANAGER)
# Fetches the latest XDM release from GitHub and runs the upstream installer.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v xdman &>/dev/null || [[ -d /opt/xdman ]]; then
    log "XDM is already installed."
    exit 0
fi

dnf_install curl tar xz
command -v java &>/dev/null || dnf_install java-latest-openjdk

url="$(github_asset_url subhra74/xdm 'xdm-setup-[0-9.]+\.tar\.xz$')"
[ -n "$url" ] || die "Could not find the XDM setup archive on GitHub"

if is_simulate; then
    url_check "$url"
    log "[simulate] would run the XDM installer from $url"
    exit 0
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Downloading $url..."
curl -fSL -o "$BUILD_DIR/xdm-setup.tar.xz" "$url"
tar xf "$BUILD_DIR/xdm-setup.tar.xz" -C "$BUILD_DIR"
chmod +x "$BUILD_DIR/install.sh"
$SUDO "$BUILD_DIR/install.sh"

log "XDM installation complete. Launch it from the app menu or run 'xdman'."
