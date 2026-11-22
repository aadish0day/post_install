#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Touchpad Setup Script (Arch Linux)
# Configures libinput (X11 only), and system-wide udev pairing for internal touchpads:
#   - Tap-to-click enabled
#   - Two-finger scrolling enabled
#   - Disable-While-Typing (DWT) enabled
#   - Flat acceleration profile
# Env: TOUCHPAD_NATURAL_SCROLL (default false), TOUCHPAD_CLICK_METHOD (default clickfinger)
# ============================================================================

# Auto-elevate to root if not already
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

# ------------------------- Options (env overrides) --------------------------
NATURAL_SCROLL="${TOUCHPAD_NATURAL_SCROLL:-false}"
CLICK_METHOD="${TOUCHPAD_CLICK_METHOD:-clickfinger}"

# ------------------------- Packages / X11 Configuration ---------------------
# xf86-input-libinput and the xorg.conf.d snippet only matter when an X server exists.
if pacman -Qq xorg-server &>/dev/null; then
    if ! pacman -Qq xf86-input-libinput &>/dev/null || ! pacman -Qq libinput &>/dev/null; then
        echo "Installing xf86-input-libinput and libinput..."
        pacman -S --needed --noconfirm xf86-input-libinput libinput
    fi

    CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"
    echo "Writing X11 touchpad settings to $CONFIG_FILE..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat <<EOL >"$CONFIG_FILE"
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "$NATURAL_SCROLL"
    Option "ClickMethod" "$CLICK_METHOD"
    Option "DisableWhileTyping" "on"
    Option "ScrollMethod" "twofinger"
    Option "AccelProfile" "flat"
EndSection
EOL
else
    echo "No X server installed; skipping X11 touchpad config (Wayland uses compositor settings)."
fi

# ------------------------- System-Wide udev / libinput Rule -----------------
# Mark built-in touchpads as "internal" so libinput pairs them with the internal keyboard (DWT).
# External USB / Bluetooth touchpads (e.g. Magic Trackpad) are excluded.
UDEV_RULE_FILE="/etc/udev/rules.d/90-touchpad.rules"
echo "Writing system-wide touchpad udev rule to $UDEV_RULE_FILE..."
mkdir -p "$(dirname "$UDEV_RULE_FILE")"
cat <<'EOF' >"$UDEV_RULE_FILE"
# Ensure internal touchpad integration for DWT and palm rejection (internal buses only)
ACTION=="add|change", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_BUS}!="usb", ENV{ID_BUS}!="bluetooth", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF

if command -v udevadm &>/dev/null; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=input 2>/dev/null || true
fi

# KDE Plasma note: Plasma reads per-device groups ([Libinput][vendor][product][name]) from
# kcminputrc, so a generic system-wide default cannot be written. Use System Settings > Touchpad.
echo "KDE Plasma: tap-to-click/scroll defaults are set in System Settings > Touchpad (per device)."
echo "Touchpad configuration completed successfully."
