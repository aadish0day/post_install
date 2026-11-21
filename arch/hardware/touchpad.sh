#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Touchpad Setup Script (Arch Linux)
# Configures libinput, system-wide udev pairing, and KDE Plasma defaults:
#   - Tap-to-click enabled
#   - Two-finger scrolling enabled
#   - Disable-While-Typing (DWT) enabled
#   - Flat acceleration profile
# ============================================================================

# Auto-elevate to root if not already
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

# ------------------------- Packages -----------------------------------------
if ! pacman -Qq xf86-input-libinput &>/dev/null || ! pacman -Qq libinput &>/dev/null; then
    echo "Installing xf86-input-libinput and libinput..."
    pacman -S --needed --noconfirm xf86-input-libinput libinput
else
    echo "libinput is already installed."
fi

# ------------------------- X11 Configuration --------------------------------
CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"
echo "Writing X11 touchpad settings to $CONFIG_FILE..."
mkdir -p "$(dirname "$CONFIG_FILE")"
cat <<'EOL' >"$CONFIG_FILE"
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"

    # Enable tap-to-click
    Option "Tapping" "on"

    # Natural scrolling is OFF
    Option "NaturalScrolling" "false"

    # Enable two-finger click method
    Option "ClickMethod" "clickfinger"

    # Disable touchpad while typing
    Option "DisableWhileTyping" "on"

    # Two-finger scrolling
    Option "ScrollMethod" "twofinger"

    # Flat pointer acceleration
    Option "AccelProfile" "flat"
EndSection
EOL

# ------------------------- System-Wide udev / libinput Rule -----------------
# Marking touchpads with ID_INPUT_TOUCHPAD_INTEGRATION="internal" ensures libinput
# pairs them with the internal keyboard for palm rejection and Disable-While-Typing (DWT).
UDEV_RULE_FILE="/etc/udev/rules.d/90-touchpad.rules"
echo "Writing system-wide touchpad udev rule to $UDEV_RULE_FILE..."
mkdir -p "$(dirname "$UDEV_RULE_FILE")"
cat <<'EOF' >"$UDEV_RULE_FILE"
# Ensure internal touchpad integration for DWT and palm rejection
ACTION=="add|change", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF

if command -v udevadm &>/dev/null; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=input 2>/dev/null || true
fi

# ------------------------- KDE Plasma Wayland Defaults ----------------------
# Tailored for KDE Plasma Wayland session (/etc/xdg/kcminputrc)
KCMINPUTRC="/etc/xdg/kcminputrc"
echo "Configuring KDE Plasma touchpad defaults in $KCMINPUTRC..."
mkdir -p "$(dirname "$KCMINPUTRC")"
if [ -f "$KCMINPUTRC" ]; then
    if ! grep -q '\[Libinput\]' "$KCMINPUTRC"; then
        cat <<'EOF' >>"$KCMINPUTRC"

[Libinput]
TapToClick=true
DisableWhileTyping=true
NaturalScroll=false
EOF
    fi
else
    cat <<'EOF' >"$KCMINPUTRC"
[Libinput]
TapToClick=true
DisableWhileTyping=true
NaturalScroll=false
EOF
fi

echo "Touchpad configuration completed successfully."
