#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA X11 PRECISION TOUCHPAD (libinput)
# Writes /etc/X11/xorg.conf.d/90-touchpad.conf. The display manager is NOT
# restarted; the settings apply on the next X login.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"

dnf_install xorg-x11-drv-libinput

log "Writing $CONFIG_FILE..."
$SUDO mkdir -p "$(dirname "$CONFIG_FILE")"
$SUDO tee "$CONFIG_FILE" >/dev/null <<'EOL'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"

    # Enable tap-to-click
    Option "Tapping" "on"

    # Enable natural scrolling (set to "false" if you prefer it disabled)
    Option "NaturalScrolling" "false"

    # Enable two-finger click method
    Option "ClickMethod" "clickfinger"

    # Disable touchpad while typing
    Option "DisableWhileTyping" "on"

    # Enable horizontal edge scrolling
    Option "HorizEdgeScroll" "true"

    # Set pointer acceleration profile to flat
    Option "AccelProfile" "flat"
EndSection
EOL

log "Touchpad configured. Log out and back in to an X11 session to apply it."
