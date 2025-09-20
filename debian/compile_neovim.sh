#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -eo pipefail

echo "Installing Neovim dependencies..."
sudo nala install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen npm

# Define the directory name to avoid repetition and where to clone
NEOVIM_DIR="neovim"
ORIGINAL_DIR=$(pwd) # Store the original directory

# Clone the Neovim repository if it doesn't already exist
if [ ! -d "$NEOVIM_DIR" ]; then
	echo "Cloning Neovim..."
	git clone https://github.com/neovim/neovim.git "$NEOVIM_DIR"
else
	echo "Directory $NEOVIM_DIR already exists, updating existing repository..."
	cd "$NEOVIM_DIR"
	git pull
	cd "$ORIGINAL_DIR"
fi

# Change directory to the cloned repository
cd "$NEOVIM_DIR" || exit 1 # Exit if changing directory fails

echo "Building Neovim..."
# Build Neovim with standard Release configuration
make CMAKE_BUILD_TYPE=Release

echo "Installing Neovim..."
# Install Neovim
sudo make install

# Return to the original directory
cd "$ORIGINAL_DIR"

# Optionally, remove the Neovim clone directory
if [ -d "$NEOVIM_DIR" ]; then
	echo "Cleaning up installation files..."
	rm -rf "$NEOVIM_DIR"
fi

echo "Neovim installation and cleanup completed successfully."
