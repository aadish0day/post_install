#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FLATPAK + FLATHUB
# Used for apps without an rpm (Android Studio, Zen, LocalSend, Obsidian).
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

dnf_install flatpak
ensure_flathub
flatpak remotes

log "Flatpak with Flathub is ready."
