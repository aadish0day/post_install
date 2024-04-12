#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Optional: set -o pipefail to ensure errors in a pipeline are detected.
set -o pipefail

echo "Installing Neovim dependencies..."
sudo nala install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen npm

# Define the directory name to avoid repetition and where to clone
NEOVIM_DIR="neovim"
ORIGINAL_DIR=$(pwd)  # Store the original directory

# Clone the Neovim repository
if [ ! -d "$NEOVIM_DIR" ]; then
    git clone https://github.com/neovim/neovim.git "$NEOVIM_DIR"
else
    echo "Directory $NEOVIM_DIR already exists, skipping clone"
fi

# Change directory to the cloned repository
cd "$NEOVIM_DIR" || exit 1  # Exit if changing directory fails

echo "Building Neovim..."
# Build Neovim with Release configuration with Debug info
make CMAKE_BUILD_TYPE=RelWithDebInfo

echo "Installing Neovim..."
# Install Neovim
sudo make install

# Return to the original directory
cd "$ORIGINAL_DIR"

# Remove the Neovim clone directory
if [ -d "$NEOVIM_DIR" ]; then
    echo "Cleaning up installation files..."
    rm -rf "$NEOVIM_DIR"
fi

echo "Neovim installation and cleanup completed successfully."

