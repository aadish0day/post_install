#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FLUTTER SDK POST-INSTALL CONFIGURATION (Arch Linux)
# ============================================================================
# The AUR flutter-bin package installs to /opt/flutter and redirects writes
# to ~/.cache/flutter_* via unionfs unless the user is in the 'flutter' group.
# Adding the user to 'flutter' gives direct write access to /opt/flutter,
# eliminating unionfs overhead, stale lock files, and unmount failures.
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Configuring Flutter SDK permissions on Arch Linux..."

# Add current user to the 'flutter' group if it exists
if getent group flutter &>/dev/null; then
    log "Adding user $USER to the 'flutter' group for direct /opt/flutter access..."
    sudo usermod -aG flutter "$USER"
fi

# Clean up stale unionfs mounts and cache from ~/.cache
if mountpoint -q "$HOME/.cache/flutter_sdk" 2>/dev/null; then
    log "Detaching active flutter_sdk unionfs mount..."
    fusermount -u -z "$HOME/.cache/flutter_sdk" 2>/dev/null || true
fi

if [ -d "$HOME/.cache/flutter_sdk" ] || [ -d "$HOME/.cache/flutter_local" ]; then
    log "Cleaning up old unionfs cache directories in ~/.cache..."
    \rm -rf "$HOME/.cache/flutter_sdk" "$HOME/.cache/flutter_local" 2>/dev/null || true
fi

log "Flutter SDK configuration complete."
log "Please log out and log back in (or run 'newgrp flutter') for group changes to take effect."
