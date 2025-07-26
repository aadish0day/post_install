#!/bin/bash

sudo apt install nala -y 
sudo nala update && sudo nala upgrade -y
sudo nala install git stow zsh tmux curl wget vim neovim -y
if [ -f ~/.zshrc ]; then
    echo "Removing existing .zshrc file..."
    rm ~/.zshrc
else
    echo ".zshrc file does not exist, nothing to remove."
fi

git clone git@github.com:aadish0day/dotfile.git ~/dotfile

cd ~/dotfile 

./link.sh
