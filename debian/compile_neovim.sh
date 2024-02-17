#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define the directory name to avoid repetition
NEOVIM_DIR="neovim"

# Clone the Neovim repository
git clone https://github.com/neovim/neovim.git "$NEOVIM_DIR"

# Change directory to the cloned repository or exit if it fails
cd "$NEOVIM_DIR" || exit

# Build Neovim with Release configuration with Debug info
make CMAKE_BUILD_TYPE=RelWithDebInfo

# Install Neovim
sudo make install

# Go back to the original directory
cd ..

# Remove the Neovim clone directory
rm -rf "$NEOVIM_DIR"

echo "Neovim installation and cleanup completed successfully."
