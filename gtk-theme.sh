#!/bin/bash

# Define the URL and destination directory
URL="https://github.com/dracula/gtk/archive/master.zip"
DEST="/usr/share/themes"

# Function to download the theme
download_theme() {
	echo "Downloading Dracula GTK theme to $DEST..."
	if sudo curl -L "$URL" -o "$DEST/theme.zip"; then
		echo "Download successful."
	else
		echo "Failed to download the theme."
		exit 1
	fi
}

# Function to extract and clean up
extract_and_cleanup() {
	echo "Extracting files..."
	if sudo unzip -q "$DEST/theme.zip" -d "$DEST"; then
		echo "Files extracted."
		sudo mv "$DEST/gtk-master" "$DEST/dracula-theme" && echo "Theme moved to final destination."
		sudo rm "$DEST/theme.zip"
		echo "Cleanup completed."
	else
		echo "Failed to extract files."
		exit 1
	fi
}

# Main execution flow
download_theme
extract_and_cleanup

# Additional check for leftover directory
if [ -d "$DEST/gtk-master" ]; then
	echo "Removing leftover directory..."
	sudo rmdir --ignore-fail-on-non-empty "$DEST/gtk-master"
fi

echo "Installation completed successfully."
