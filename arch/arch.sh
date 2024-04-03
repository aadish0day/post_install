
#!/bin/bash

# Update system and packages
sudo pacman -Syu --noconfirm

sudo pacman -S reflector

sudo reflector --latest 5 --country India --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Install packages
sudo pacman -S --noconfirm neovim ranger ncdu mpv maven yt-dlp fzf git unzip nodejs ninja gettext libtool autoconf automake cmake gcc pkgconf htop doxygen flameshot npm xclip ueberzug highlight atool mediainfo neofetch android-tools img2pdf zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb obs-studio picom nitrogen

# For AUR helper installation (yay or paru), uncomment and adjust the following:
# git clone https://aur.archlinux.org/yay.git
# cd yay
# makepkg -si
# cd ..
# rm -rf yay


echo "Installation and setup complete on Arch Linux."
