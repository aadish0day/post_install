#!/usr/bin/env bash

# Exit on any error
set -e

# Update the system
echo "Updating Termux..."
pkg update && pkg upgrade -y

# Install required packages
echo "Installing packages..."
pkg install -y git python vim neovim tmux zsh curl wget fzf lsd bat zoxide startship ani-cli git-lfs

# Install Starship if not already installed
# Setup Termux storage
echo "Setting up Termux storage..."
termux-setup-storage

# Clone dotfiles only if it doesn't already exist
if [ ! -d ~/dotfile ]; then
	echo "Cloning dotfiles..."
	if git clone https://github.com/aadish0day/dotfile.git ~/dotfile; then
		echo "Dotfiles cloned successfully."
		# Link dotfiles if link.sh exists
		if [ -f ~/dotfile/link.sh ]; then
			cd ~/dotfile
			./link.sh
			cd - >/dev/null
		fi
	fi
else
	echo "Dotfiles directory already exists. Skipping clone."
fi

# Change default shell to zsh
if command -v zsh &>/dev/null; then
	chsh -s "$(command -v zsh)"
fi

echo "Termux setup completed successfully!"
