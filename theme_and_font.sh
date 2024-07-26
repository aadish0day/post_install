#!/bin/bash

# Define the URL and destination directory for the GTK theme
GTK_URL="https://github.com/dracula/gtk/archive/master.zip"
GTK_DEST="/usr/share/themes"

# Function to download the GTK theme
download_gtk_theme() {
	echo "Downloading Dracula GTK theme to $GTK_DEST..."
	if sudo curl -L "$GTK_URL" -o "$GTK_DEST/theme.zip"; then
		echo "Download successful."
	else
		echo "Failed to download the theme."
		exit 1
	fi
}

# Function to extract the GTK theme and clean up
extract_gtk_theme() {
	echo "Extracting files..."
	if sudo unzip -q "$GTK_DEST/theme.zip" -d "$GTK_DEST"; then
		echo "Files extracted."
		sudo mv "$GTK_DEST/gtk-master" "$GTK_DEST/dracula-theme" && echo "Theme moved to final destination."
		sudo rm "$GTK_DEST/theme.zip"
		echo "Cleanup completed."
	else
		echo "Failed to extract files."
		exit 1
	fi
}

# Main execution flow for GTK theme
download_gtk_theme
extract_gtk_theme

# Additional check for leftover directory
if [ -d "$GTK_DEST/gtk-master" ]; then
	echo "Removing leftover directory..."
	sudo rmdir --ignore-fail-on-non-empty "$GTK_DEST/gtk-master"
fi

echo "GTK theme installation completed successfully."

# Define the repository URL and the directory name for the icon theme
ICON_REPO_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git"
ICON_DIR_NAME="papirus-icon-theme"

# Function to clone the icon theme repository
clone_icon_repo() {
	echo "Cloning Papirus icon theme from $ICON_REPO_URL..."
	if git clone "$ICON_REPO_URL"; then
		echo "Repository cloned successfully."
	else
		echo "Failed to clone the repository."
		exit 1
	fi
}

# Function to install the icon theme
install_icon_theme() {
	if [ -d "$ICON_DIR_NAME" ]; then
		echo "Installing Papirus icon theme..."
		cd "$ICON_DIR_NAME" && sudo ./install.sh
		echo "Installation complete!"
	else
		echo "Directory $ICON_DIR_NAME does not exist."
		exit 1
	fi
}

# Main execution flow for icon theme
clone_icon_repo
install_icon_theme

# Define the directory to store fonts
FONTS_DIR="${HOME}/.local/share/fonts"

# Create the directory if it does not exist
if [ ! -d "${FONTS_DIR}" ]; then
	echo "Creating directory: $FONTS_DIR"
	mkdir -p "${FONTS_DIR}"
else
	echo "Found existing fonts directory: $FONTS_DIR"
fi

# GitHub repository from which to fetch the latest release
FONT_REPO="ryanoasis/nerd-fonts"

# Fetch the latest release tag from GitHub API
echo "Fetching the latest release information..."
LATEST_RELEASE_JSON=$(curl -s "https://api.github.com/repos/$FONT_REPO/releases/latest")

# Extract the tag name (version) from the JSON response
LATEST_VERSION=$(echo "$LATEST_RELEASE_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Check if we got a version number
if [[ -z "$LATEST_VERSION" ]]; then
	echo "Failed to fetch the latest version number." >&2
	exit 1
fi

echo "Latest version is $LATEST_VERSION"

# Define the filename based on expected zip file format
ZIP="FiraMono.zip"

# Download the zip file using the latest version number
echo "Downloading Fira Mono Nerd Font version $LATEST_VERSION..."
if curl --fail --location --show-error -o "${ZIP}" "https://github.com/$FONT_REPO/releases/download/$LATEST_VERSION/$ZIP"; then
	echo "Download successful."
else
	echo "Failed to download the font zip file." >&2
	exit 1
fi

# Unzip the font files into the designated directory
echo "Unzipping the font files..."
unzip -o -q -d "${FONTS_DIR}" "${ZIP}"

# Clean up by removing the zip file after extraction
echo "Removing zip file..."
rm "${ZIP}"

# Update the font cache
echo "Updating font cache..."
fc-cache -f

echo "Font installation completed."
