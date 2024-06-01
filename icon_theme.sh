#!/bin/bash

# Define the repository URL and the directory name
REPO_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git"
DIR_NAME="papirus-icon-theme"

# Function to clone the repository
clone_repo() {
	echo "Cloning Papirus icon theme from $REPO_URL..."
	if git clone "$REPO_URL"; then
		echo "Repository cloned successfully."
	else
		echo "Failed to clone the repository."
		exit 1
	fi
}

# Function to install the icon theme
install_icon_theme() {
	if [ -d "$DIR_NAME" ]; then
		echo "Installing Papirus icon theme..."
		cd "$DIR_NAME" && sudo ./install.sh
		echo "Installation complete!"
	else
		echo "Directory $DIR_NAME does not exist."
		exit 1
	fi
}

# Main execution flow
clone_repo
install_icon_theme
