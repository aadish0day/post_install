#!/bin/bash

# Define the URL and destination directory
URL="https://github.com/dracula/gtk/archive/master.zip"
DEST="/usr/share/themes"

# Ensure running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Download the ZIP file directly into the destination directory
echo "Downloading Dracula GTK theme..."
curl -L "$URL" -o "$DEST/theme.zip"

# Extract the contents of the ZIP file and clean up
echo "Extracting files..."
unzip "$DEST/theme.zip" -d "$DEST"
mv "$DEST/gtk-master" "$DEST/dracula-theme"
rm "$DEST/theme.zip"

# Remove the original extracted directory structure if it's empty
rmdir --ignore-fail-on-non-empty "$DEST/gtk-master"

echo "Installation completed successfully."

