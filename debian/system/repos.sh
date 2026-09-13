#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEBIAN / UBUNTU REPOSITORY SETUP
# Enables contrib/non-free/non-free-firmware (Debian) or universe/multiverse
# (Ubuntu), adds the i386 architecture for 32-bit gaming libraries, and
# installs the tools the other scripts rely on.
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if is_ubuntu; then
    log "Ubuntu detected - enabling universe and multiverse..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y software-properties-common
    $SUDO add-apt-repository -y universe
    $SUDO add-apt-repository -y multiverse
else
    components="main contrib non-free non-free-firmware"

    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        log "Enabling '$components' in debian.sources..."
        $SUDO sed -i -E "s/^Components:.*/Components: $components/" /etc/apt/sources.list.d/debian.sources
    fi

    if [ -f /etc/apt/sources.list ] && grep -qE '^deb .*debian' /etc/apt/sources.list; then
        log "Enabling '$components' in sources.list..."
        $SUDO sed -i -E "/^deb(-src)? .*debian/ s/ main( .*)?$/ $components/" /etc/apt/sources.list
    fi
fi

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Adding i386 architecture (32-bit libraries for Wine/Steam)..."
    $SUDO dpkg --add-architecture i386
fi

apt_force_update
log "Installing repository tooling..."
$SUDO apt-get install -y nala curl wget ca-certificates gnupg apt-transport-https lsb-release

log "Repository setup complete."
