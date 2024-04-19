#!/bin/bash

# Define the repository URL and the directory name
REPO_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git"
DIR_NAME="papirus-icon-theme"

# Clone the repository
echo "Cloning Papirus icon theme..."
git clone $REPO_URL

# Check if the directory exists and install the icon pack
if [ -d "$DIR_NAME" ]; then
    echo "Installing Papirus icon theme..."
    cd "$DIR_NAME"
    sudo ./install.sh
    echo "Installation complete!"
else
    echo "Failed to clone the repository."
    exit 1
fi

