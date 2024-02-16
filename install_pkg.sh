#!/bin/bash

echo "Select your distribution:"
echo "1) Debian/Ubuntu"
echo "2) Arch Linux"
echo "3) Fedora"
read -p "Distribution (1/2/3): " DISTRO_CHOICE

case $DISTRO_CHOICE in
  1)
    cd debian && ./debian.sh
    ;;
  2)
    cd arch && ./arch.sh
    ;;
  3)
    cd fedora && ./fedora.sh
    ;;
  *)
    echo "Invalid selection. Exiting."
    exit 1
    ;;
esac

