#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FLATPAK + FLATHUB
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Setting up Flatpak with the Flathub remote..."
apt_install flatpak
if ! is_simulate; then
    ensure_flatpak
fi

# Integrate with the software centre when a desktop is present
if pkg_installed plasma-discover; then
    apt_install plasma-discover-backend-flatpak
elif pkg_installed gnome-software; then
    apt_install gnome-software-plugin-flatpak
fi

log "Flatpak setup complete. Log out and back in for app menu integration."
