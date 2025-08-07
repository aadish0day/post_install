#!/bin/bash
set -euo pipefail

# Install nala and update/upgrade system
sudo apt update
sudo apt install nala -y
sudo nala update && sudo nala full-upgrade -y

# Install necessary packages
sudo nala install git stow zsh tmux curl wget vim neovim fzf starship zoxide lsd trash-cli -y

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

cd ~/dotfile
./link.sh

# Prompt user to choose Kali metapackages
echo
echo "Choose Kali metapackages to install (you can select multiple by separating with space):"
echo "1) kali-linux-everything  - All Kali tools (large download, ~10GB+)"
echo "2) kali-linux-large       - Extended default toolset"
echo "3) kali-linux-labs        - Vulnerable lab environments"
echo "4) Skip this step"

read -rp "Enter your choices [1-4], separated by spaces: " -a choices

for choice in "${choices[@]}"; do
    case $choice in
    1)
        echo "Installing kali-linux-everything..."
        sudo nala install kali-linux-everything -y
        ;;
    2)
        echo "Installing kali-linux-large..."
        sudo nala install kali-linux-large -y
        ;;
    3)
        echo "Installing kali-linux-labs..."
        sudo nala install kali-linux-labs -y
        ;;
    4)
        echo "Skipping metapackage installation."
        ;;
    *)
        echo "Invalid choice: $choice"
        ;;
    esac
done
