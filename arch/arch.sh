
#!/bin/bash

# Update system and packages
sudo pacman -Syu --noconfirm

sudo pacman -S reflector

sudo reflector --latest 5 --country India --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Install packages
sudo pacman -S --noconfirm neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf htop doxygen flameshot npm xclip ueberzug highlight atool mediainfo neofetch android-tools img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen starship xss-lock 


echo "Installation and setup complete on Arch Linux."
