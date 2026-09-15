#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# X11 PRECISION TOUCHPAD (libinput)
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"

apt_install xserver-xorg-input-libinput

if is_simulate; then
    log "[simulate] would write $CONFIG_FILE"
    exit 0
fi

log "Writing $CONFIG_FILE..."
$SUDO install -d -m 0755 /etc/X11/xorg.conf.d
$SUDO tee "$CONFIG_FILE" >/dev/null <<'EOL'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"

    # Enable tap-to-click
    Option "Tapping" "on"

    # Natural scrolling (set to "true" to enable)
    Option "NaturalScrolling" "false"

    # Two-finger click method
    Option "ClickMethod" "clickfinger"

    # Disable touchpad while typing
    Option "DisableWhileTyping" "on"

    # Horizontal edge scrolling
    Option "HorizEdgeScroll" "true"

    # Flat pointer acceleration profile
    Option "AccelProfile" "flat"
EndSection
EOL

log "Touchpad configuration written. Log out and back in (or restart X) to apply it."
