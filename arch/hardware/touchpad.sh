#!/usr/bin/env bash
set -euo pipefail

# Check if the script is run as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

# Update system
echo "Updating system..."
pacman -Syu --noconfirm

# Define the target configuration file path for touchpad
CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"

# Check if libinput is installed
if ! pacman -Qs xf86-input-libinput >/dev/null; then
    echo "libinput is not installed. Installing xf86-input-libinput..."
    pacman -S --noconfirm xf86-input-libinput
else
    echo "libinput is already installed."
fi

# Create the configuration file or overwrite it with the merged settings
echo "Creating/overwriting $CONFIG_FILE with touchpad settings..."

cat <<EOL >$CONFIG_FILE
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

    # Scrolling configuration: libinput defaults to twofinger scrolling.
    # Set Option "ScrollMethod" "edge" to enable edge scrolling instead.
    Option "ScrollMethod" "twofinger"
    # Legacy synaptics compatibility option:
    Option "HorizEdgeScroll" "true"

    # Set pointer acceleration profile to flat
    Option "AccelProfile" "flat"
EndSection
EOL

# Reload udev rules to apply changes for new input events without terminating the active session
echo "Reloading udev rules to apply touchpad settings..."
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=input 2>/dev/null || true

echo "Touchpad configuration complete. Changes will take full effect on your next session."
