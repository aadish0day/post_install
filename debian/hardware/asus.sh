#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ASUS ROG setup (Debian/Ubuntu)
# asusctl isn't packaged for Debian, so it is built from source following the
# upstream README. CPU/GPU drivers live in gpu/amd.sh, gpu/nvidia.sh, gpu/intel.sh.
#
# Usage: asus.sh [battery_limit]   (default: 85)
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

BATTERY_LIMIT="${1:-85}"
ASUSCTL_REPO="https://github.com/OpenGamingCollective/asusctl.git"

log "Installing asusctl build dependencies..."
apt_install git make cmake build-essential pkg-config clang libclang-dev libudev-dev libfontconfig-dev \
    libxkbcommon-dev libseat-dev libinput-dev libgbm-dev libexpat1-dev libssl-dev libzstd-dev \
    libpcre2-dev libgtk-3-dev power-profiles-daemon curl

if is_simulate; then
    git ls-remote --exit-code "$ASUSCTL_REPO" HEAD >/dev/null || die "asusctl repository not reachable"
    url_ok https://sh.rustup.rs >/dev/null || die "rustup not reachable"
    log "[simulate] would build and install asusctl from $ASUSCTL_REPO"
    exit 0
fi

# Rust stable toolchain (Debian's rustc is often too old for asusctl)
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
    log "Installing the Rust toolchain with rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
export PATH="$HOME/.cargo/bin:$PATH"

if command -v asusctl >/dev/null 2>&1; then
    log "asusctl is already installed: $(asusctl --version 2>/dev/null | head -n1)"
else
    BUILD_DIR="$(mktemp -d /tmp/asusctl_build_XXXXXX)"
    trap 'rm -rf "$BUILD_DIR"' EXIT

    log "Cloning asusctl..."
    git clone --depth 1 "$ASUSCTL_REPO" "$BUILD_DIR/asusctl"

    log "Building asusctl (this takes a few minutes)..."
    make -C "$BUILD_DIR/asusctl"

    log "Installing asusctl..."
    $SUDO env "PATH=$PATH" make -C "$BUILD_DIR/asusctl" install
fi

enable_service power-profiles-daemon.service --now
enable_service asusd.service --now

if in_container; then
    warn "Container detected, skipping asusctl battery limit and fan curve configuration."
    exit 0
fi

log "Setting battery charge limit to ${BATTERY_LIMIT}%..."
asusctl battery limit "$BATTERY_LIMIT" || warn "Could not set battery limit (is asusd running?)"

# asusd drops consecutive writes; pause between profiles
log "Enabling custom fan curves..."
for profile in Quiet Performance Balanced; do
    asusctl fan-curve --mod-profile "$profile" --enable-fan-curves true || warn "Fan curve for $profile failed"
    sleep 1
done

log "ASUS setup complete."
