#!/bin/bash

# Check if the script is run as root (auto-elevate if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E "$0" "$@"
fi

# Update system
# Updating the system to make sure all packages are up to date before installing new ones
echo "Updating system..."
pacman -Syu --noconfirm

# Install necessary packages for AMD
# Installing the required packages for AMD GPU support, Vulkan, and other dependencies
echo "Installing necessary AMD packages..."
sudo pacman -S --noconfirm xf86-video-amdgpu amd-ucode vulkan-radeon lib32-vulkan-radeon radeontop mesa lib32-mesa lib32-mesa-vdpau mesa-vdpau amdvlk lib32-amdvlk lib32-libva-mesa-driver libva-mesa-driver dkms rocm-opencl-runtime rocm-opencl-sdk  opencl-headers libclc ocl-icd lib32-ocl-icd   glu mesa-utils mesa-demos vulkan-mesa-layers lib32-glu lib32-mesa-utils lib32-mesa-demos lib32-vulkan-mesa-layers mesa-vdpau lib32-mesa-vdpau

# Edit GRUB configuration to optimize for AMD
# Uncomment and modify if needed
echo "Editing GRUB configuration..."
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 amdgpu.dpm=1 amdgpu.audio=0 amdgpu.runpm=1 pcie_aspm=force amdgpu.ppfeaturemask=0xffffbfff amdgpu.deep_color=1 amdgpu.hw_i2c=1 amdgpu.gttsize=8192 iommu=pt idle=nomwait amd_pstate=active amd_prefcore=enable radeon.si_support=0 radeon.cik_support=0  "|' /etc/default/grub

# Regenerate the GRUB configuration
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "AMD drivers installed and GRUB configuration updated."

# Define the target configuration file path for touchpad
# The configuration file for touchpad settings will be created/overwritten here
CONFIG_FILE="/etc/X11/xorg.conf.d/90-touchpad.conf"

# Check if libinput is installed
# Ensuring that libinput (the touchpad driver) is installed, if not, it will be installed
if ! pacman -Qs xf86-input-libinput >/dev/null; then
    echo "libinput is not installed. Installing xf86-input-libinput..."
    pacman -S --noconfirm xf86-input-libinput

    # Check if the installation was successful
    if [ $? -eq 0 ]; then
        echo "libinput has been installed successfully."
    else
        echo "Failed to install libinput. Exiting script."
        exit 1
    fi
else
    echo "libinput is already installed."
fi

# Create the configuration file or overwrite it with the merged settings
# The script creates or updates the touchpad settings in the configuration file for Xorg
echo "Creating/overwriting $CONFIG_FILE with touchpad settings..."

cat <<EOL >$CONFIG_FILE
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"

    # Enable tap-to-click
    Option "Tapping" "on"

    # Enable natural scrolling (set to "false" if you prefer it disabled)
    Option "NaturalScrolling" "false"

    # Enable two-finger click method
    Option "ClickMethod" "clickfinger"

    # Disable touchpad while typing
    Option "DisableWhileTyping" "on"

    # Enable horizontal edge scrolling
    Option "HorizEdgeScroll" "true"

    # Set pointer acceleration profile to flat
    Option "AccelProfile" "flat"
EndSection
EOL

# Check if the configuration file was successfully created
# Verifies if the file was written to successfully
if [ $? -eq 0 ]; then
    echo "Touchpad configuration has been successfully applied to $CONFIG_FILE."
else
    echo "Failed to create or write to $CONFIG_FILE."
    exit 1
fi

# Restart X to apply changes
# Restart the display manager to apply the touchpad configuration
echo "Restarting X session to apply changes..."
systemctl restart display-manager

echo "Touchpad configuration complete. Please test the settings."
