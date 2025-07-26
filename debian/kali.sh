#!/bin/bash

# Install nala and update/upgrade system
sudo apt install nala -y
sudo nala update && sudo nala upgrade -y

# Install necessary packages
sudo nala install git stow zsh tmux curl wget vim neovim fzf starship zoxide -y

# Remove existing .zshrc if it exists
if [ -f ~/.zshrc ]; then
	echo "Removing existing .zshrc file..."
	rm ~/.zshrc
else
	echo ".zshrc file does not exist, nothing to remove."
fi

# Clone dotfiles only if it doesn't already exist
if [ -d ~/dotfile ]; then
	echo "Directory ~/dotfile already exists. Skipping clone."
else
	echo "Cloning dotfiles..."
	git clone https://github.com/aadish0day/dotfile.git ~/dotfile
fi

# Navigate and link
cd ~/dotfile
./link.sh
