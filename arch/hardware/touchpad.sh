#!/usr/bin/env bash
set -euo pipefail

# Check if the script is run as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

# Define the target configuration file path for touchpad
CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"

# Check if libinput is installed
if ! pacman -Qq xf86-input-libinput &>/dev/null; then
    echo "libinput is not installed. Installing xf86-input-libinput..."
    pacman -S --needed --noconfirm xf86-input-libinput
else
    echo "libinput is already installed."
fi

# Create the configuration file or overwrite it with the merged settings
echo "Creating/overwriting $CONFIG_FILE with touchpad settings..."

mkdir -p "$(dirname "$CONFIG_FILE")"
cat <<EOL >"$CONFIG_FILE"
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"

    # Enable tap-to-click
    Option "Tapping" "on"

    # Natural scrolling is OFF here (set to "true" to enable it)
    Option "NaturalScrolling" "false"

    # Enable two-finger click method
    Option "ClickMethod" "clickfinger"

    # Disable touchpad while typing
    Option "DisableWhileTyping" "on"

    # Scrolling configuration: libinput defaults to twofinger scrolling.
    # Set Option "ScrollMethod" "edge" to enable edge scrolling instead.
    Option "ScrollMethod" "twofinger"

    # Set pointer acceleration profile to flat
    Option "AccelProfile" "flat"
EndSection
EOL

echo "Touchpad configuration written to $CONFIG_FILE."
echo "Xorg reads it at start: log out and back in (or restart X) to apply."
