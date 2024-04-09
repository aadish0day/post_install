#!/bin/bash

# Update system and databases
yay -Syu --noconfirm

# Install packages
yay -S --noconfirm i3lock-color
yay -S --noconfirm thorium-browser-bin
yay -S --noconfirm vscodium-bin
yay -S --noconfirm github-desktop-bin
yay -S --noconfirm mocp
yay -S --noconfirm ani-cli
yay -S --noconfirm hakuneko-desktop

echo "Installation of packages completed!"

