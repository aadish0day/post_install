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

# 0. ASUS hardware only. The TUI lets people enable this on any machine (and the
#    run log showed it running in a QEMU guest), so gate it at runtime like the
#    gpu/ scripts do. Mirrors core/detector.py's vendor check.
has_asus_hardware() {
    local combined
    combined="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name \
        /sys/class/dmi/id/product_family 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$combined" in
    *asus* | *rog* | *tuf* | *zephyrus* | *strix* | *zenbook*) return 0 ;;
    *) return 1 ;;
    esac
}

# mask_unit UNIT...  (only units that actually exist on this system)
mask_unit() {
    local unit
    for unit in "$@"; do
        systemctl cat "$unit" &>/dev/null || continue
        log "Masking $unit"
        $SUDO systemctl mask --now "$unit" || warn "Could not mask $unit"
    done
}

if ! has_asus_hardware; then
    log "No ASUS hardware detected - skipping ASUS ROG setup."
    exit 0
fi

# 1. Terra repository, restricted to asusctl packages
terra_enable
if ! grep -q '^includepkgs=' "$TERRA_REPO"; then
    $SUDO sed -i '/^\[terra\]/a includepkgs=asusctl* supergfxctl* terra-release*' "$TERRA_REPO"
    log "Limited Terra to ASUS packages"
fi

# 2. Packages
$SUDO dnf makecache -y --repo terra >/dev/null
dnf_install --strict asusctl asusctl-rog-gui

# 3. Power profiles
# asusd manages platform profiles and CPU EPP itself, and a second daemon
# (tuned-ppd on Fedora, or power-profiles-daemon) fights it for the same knobs.
# Per the asusctl Fedora guide, let asusd own them and mask the external daemon.
# Never install power-profiles-daemon here: it conflicts with tuned-ppd's
# ppd-service and aborts the transaction.
if rpm -q power-profiles-daemon &>/dev/null; then
    mask_unit power-profiles-daemon.service
fi
if rpm -q tuned &>/dev/null || rpm -q tuned-ppd &>/dev/null; then
    mask_unit tuned.service tuned-ppd.service
fi

# asusd is triggered by a udev rule; enabling it here is belt-and-braces.
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
