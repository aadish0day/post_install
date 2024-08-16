#!/bin/bash

# Update system
sudo pacman -Syu --noconfirm

# Install necessary packages for AMD
sudo pacman -S --noconfirm xf86-video-amdgpu amd-ucode vulkan-radeon lib32-vulkan-radeon radeontop mesa lib32-mesa lib32-mesa-vdpau mesa-vdpau amdvlk lib32-amdvlk lib32-libva-mesa-driver libva-mesa-driver dkms

# Create Xorg configuration if it doesn't exist
if [ ! -f /etc/X11/xorg.conf.d/20-amdgpu.conf ]; then
	sudo mkdir -p /etc/X11/xorg.conf.d
	sudo tee /etc/X11/xorg.conf.d/20-amdgpu.conf >/dev/null <<EOL
    Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"               # Prevent screen tearing
    Option "DRI" "3"                       # Enable Direct Rendering Infrastructure 3 for better performance
    Option "AccelMethod" "glamor"          # Use glamor for 2D acceleration
    Option "VariableRefresh" "true"        # Enable variable refresh rate (if supported)
    Option "PowerPlay" "true"              # Enable PowerPlay for better power management
    Option "EnablePageFlip" "true"         # Enable page flipping for better performance
    Option "Backlight" "amdgpu_bl0"        # Control backlight
    EndSection
EOL
	echo "Xorg configuration for AMD created at /etc/X11/xorg.conf.d/20-amdgpu.conf."
else
	echo "Xorg configuration file already exists at /etc/X11/xorg.conf.d/20-amdgpu.conf."
fi

# Edit GRUB configuration
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nowatchdog nvme_load=YES loglevel=3 amdgpu.dpm=1 amdgpu.audio=0 amdgpu.runpm=1 amdgpu.powersave=1 pcie_aspm=force amdgpu.ppfeaturemask=0xffffffff iommu=pt idle=nomwait"|' /etc/default/grub

# Update GRUB configuration
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "AMD drivers installed."
