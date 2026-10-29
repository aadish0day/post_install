#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA XDM (XTREME DOWNLOAD MANAGER)
# Fetches the latest XDM release from GitHub and installs the RPM package.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v xdman &>/dev/null || [[ -d /opt/xdman ]]; then
    log "XDM is already installed."
    exit 0
fi

dnf_install curl
command -v java &>/dev/null || dnf_install java-latest-openjdk

url="$(github_asset_url subhra74/xdm 'xdm-.*\.x86_64\.rpm$')"
[ -n "$url" ] || die "Could not find the XDM rpm package on GitHub"

if is_simulate; then
    url_check "$url"
    log "[simulate] would install XDM from $url"
    exit 0
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Downloading $url..."
curl -fSL -o "$BUILD_DIR/xdm.rpm" "$url"
$SUDO dnf install -y "$BUILD_DIR/xdm.rpm"

log "XDM installation complete. Launch it from the app menu or run 'xdman'."
