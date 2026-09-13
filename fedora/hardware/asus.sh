#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA ASUS ROG SETUP
# asusctl + its ROG Control Center GUI (asusctl-rog-gui) from the Terra repository (the source the
# asusctl README recommends for Fedora). Terra is limited to the ASUS
# packages so it can't replace other Fedora packages.
#
# Usage: asus.sh [battery_limit]   (default: 85)
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

BATTERY_LIMIT="${1:-85}"
TERRA_REPO="/etc/yum.repos.d/terra.repo"

# 1. Terra repository, restricted to asusctl packages
terra_enable
if ! grep -q '^includepkgs=' "$TERRA_REPO"; then
    $SUDO sed -i '/^\[terra\]/a includepkgs=asusctl* supergfxctl* terra-release*' "$TERRA_REPO"
    log "Limited Terra to ASUS packages"
fi

# 2. Packages
$SUDO dnf makecache -y --repo terra >/dev/null
dnf_install --strict asusctl asusctl-rog-gui power-profiles-daemon

# 3. Services
enable_service power-profiles-daemon.service --now
enable_service asusd.service --now

# 4. asusctl configuration (needs the asusd daemon on real hardware)
if in_container || is_simulate; then
    warn "Skipping asusctl battery/fan-curve configuration (no asusd here)."
elif ! command -v asusctl &>/dev/null; then
    warn "asusctl not installed; skipping configuration."
else
    log "Setting battery charge limit to ${BATTERY_LIMIT}%..."
    asusctl battery limit "$BATTERY_LIMIT"

    # asusd races on consecutive writes; pause between fan-curve profiles
    log "Enabling custom fan curves..."
    asusctl fan-curve --mod-profile Quiet --enable-fan-curves true
    sleep 1
    asusctl fan-curve --mod-profile Performance --enable-fan-curves true
    sleep 1
    asusctl fan-curve --mod-profile Balanced --enable-fan-curves true
fi

log "ASUS ROG setup complete. CPU/GPU drivers: run gpu/amd.sh, gpu/nvidia.sh or gpu/intel.sh."
