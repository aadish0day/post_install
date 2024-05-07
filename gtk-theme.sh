#!/bin/bash

# Define the URL and destination directory
URL="https://github.com/dracula/gtk/archive/master.zip"
DEST="/usr/share/themes"

# Download the ZIP file directly into the destination directory
echo "Downloading Dracula GTK theme..."
sudo curl -L "$URL" -o "$DEST/theme.zip"

# Extract the contents of the ZIP file and clean up
echo "Extracting files..."
sudo unzip "$DEST/theme.zip" -d "$DEST"
sudo mv "$DEST/gtk-master" "$DEST/dracula-theme"
sudo rm "$DEST/theme.zip"

# Remove the original extracted directory structure if it's empty
sudo rmdir --ignore-fail-on-non-empty "$DEST/gtk-master"

echo "Installation completed successfully."
