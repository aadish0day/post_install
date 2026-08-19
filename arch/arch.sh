#!/usr/bin/env bash
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt_yes_no() {
    local res
    echo ""
    read -rp "$1 (y/n): " res
    [[ "$res" =~ ^[Yy]$ ]]
}

# Keep sudo alive during long operations (e.g., AUR builds)
if sudo -v; then
    sudo -n true
    keep_sudo_alive() { while true; do
        sleep 60
        sudo -n true
    done; }
    keep_sudo_alive &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill ${SUDO_KEEP_ALIVE_PID} 2>/dev/null || true' EXIT
fi

# Update system and packages
echo "Updating system and packages..."
sudo pacman -Sy --noconfirm
sudo pacman -S --needed reflector --noconfirm --overwrite '*'

# Prompt user to configure mirrors
if prompt_yes_no "Do you want to configure the mirror list for India using reflector?"; then
    echo "Configuring mirror list strictly for India (with 30s timeout)..."
    timeout 30s sudo reflector --latest 10 --fastest 5 --protocol https --connection-timeout 5 --download-timeout 5 --threads 8 --country India --sort rate --save /etc/pacman.d/mirrorlist || echo "Reflector timed out or failed; keeping existing mirrorlist."
fi

# Update system and packages after mirror update
sudo pacman -Syu --noconfirm --overwrite '*'

# ============================================================================
# ASK USER PREFERENCES UPFRONT
# ============================================================================

echo ""
echo "=========================================="
echo "Desktop Environment Selection"
echo "=========================================="
echo "1) KDE Plasma"
echo "2) X11 Tiling Window Manager"
echo "3) None (Skip desktop environment)"
echo ""
read -rp "Select desktop environment (1-3): " de_choice

install_kde=false
install_x11=false

case $de_choice in
1)
    install_kde=true
    echo "KDE Plasma will be installed."
    ;;
2)
    install_x11=true
    echo "X11 tiling window manager packages will be installed."
    ;;
3)
    echo "Skipping desktop environment installation."
    ;;
*)
    echo "Invalid choice. Skipping desktop environment installation."
    ;;
esac

# Ask preferences
echo ""
echo "=========================================="
echo "AUR Helper Selection"
echo "=========================================="
echo "1) Paru (Rust, Recommended)"
echo "2) Yay (Go, Classic)"
echo "3) Both (Paru & Yay)"
echo ""
read -rp "Select AUR Helper (1-3, Default: 1): " aur_choice
aur_choice="${aur_choice:-1}"

install_gaming=false
prompt_yes_no "Do you want to install gaming packages?" && install_gaming=true
install_asus=false
prompt_yes_no "Do you want to install ASUS specific drivers?" && install_asus=true
install_virt=false
prompt_yes_no "Do you want to install virtualization packages (VMware Workstation and Open VM Tools)?" && install_virt=true
install_docker=false
prompt_yes_no "Do you want to install Docker?" && install_docker=true
install_amd=false
prompt_yes_no "Do you want to install AMD GPU drivers and runtimes (Vulkan/OpenCL/VA-API/VDPAU)?" && install_amd=true
install_aiml=false
prompt_yes_no "Do you want to install AI/ML packages (ROCm, PyTorch, ONNX Runtime, etc.)?" && install_aiml=true
install_coding=false
prompt_yes_no "Do you want to install coding packages (VS Code, Android Studio, Flutter, etc.)?" && install_coding=true
install_burp=false
prompt_yes_no "Do you want to install Burp Suite Professional?" && install_burp=true

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
# Determine which desktop environment was selected
de_name="None"
if [ "$install_kde" = true ]; then
    de_name="KDE Plasma"
elif [ "$install_x11" = true ]; then
    de_name="X11 Tiling"
fi

aur_name="Paru"
case "$aur_choice" in
    1) aur_name="Paru" ;;
    2) aur_name="Yay" ;;
    3) aur_name="Both (Paru + Yay)" ;;
    *) aur_name="Paru" ;;
esac

echo "Desktop Environment: $de_name"
echo "AUR Helper: $aur_name"
echo "Gaming Packages: $([ "$install_gaming" = true ] && echo "Yes" || echo "No")"
echo "ASUS Drivers: $([ "$install_asus" = true ] && echo "Yes" || echo "No")"
echo "Virtualization Packages: $([ "$install_virt" = true ] && echo "Yes" || echo "No")"
echo "Docker: $([ "$install_docker" = true ] && echo "Yes" || echo "No")"
echo "AMD Drivers: $([ "$install_amd" = true ] && echo "Yes" || echo "No")"
echo "AI/ML Packages: $([ "$install_aiml" = true ] && echo "Yes" || echo "No")"
echo "Coding Packages: $([ "$install_coding" = true ] && echo "Yes" || echo "No")"
echo "Burp Suite Professional: $([ "$install_burp" = true ] && echo "Yes" || echo "No")"
echo "=========================================="
echo ""
read -rp "Continue with installation? (y/n): " continue_install
if [[ ! $continue_install =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to install packages if not already installed
install_if_needed() {
    sudo pacman -S --needed --noconfirm --overwrite '*' "$@"
}

# Function to install AUR packages
install_aur_packages() {
    if command -v paru &>/dev/null; then
        paru -S --needed --noconfirm "$@"
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm "$@"
    else
        echo "Warning: No AUR helper found. Skipping AUR packages: $*"
    fi
}

# ============================================================================
# PACKAGE LISTS
# ============================================================================

# List of general packages
packages=(
    android-tools aria2 atool bat cantarell-fonts chromaprint doxygen duf fastfetch fd ffmpegthumbnailer
    fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs
    gvfs-smb highlight htop img2pdf imagemagick inxi jq jpegoptim kitty less libavtp libdca libgme liblrdf libltc
    libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv mpv-mpris ncdu
    neovim nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra npm obs-studio p7zip pacman-contrib pacutils
    papirus-icon-theme parallel pipewire pipewire-alsa pipewire-audio pipewire-jack lib32-pipewire-jack pipewire-pulse pipewire-zeroconf pipewire-libcamera
    pkgfile plocate playerctl pv qalculate-qt qbittorrent ripgrep sd spandsp starship soundtouch svt-hevc tar
    tree tree-sitter-cli trash-cli tmux ttf-jetbrains-mono ttf-jetbrains-mono-nerd tumbler unzip wireplumber xz
    yazi yt-dlp zip zoxide zsh zstd dosfstools usbutils lazydocker opencode github-cli
)

# List of AUR packages
aur_packages=(
    "advcpmv"
    "ani-cli"
    "anydesk-bin"
    "gallery-dl-bin"
    "localsend-bin"
    "markitdown-bin"
    "thorium-browser-bin"
    # "timeshift-autosnap"
    "vesktop-bin"
    # "xdman"
    "zen-browser-bin"
    "antigravity"
)

# List of coding-specific AUR packages
aur_coding_packages=(
    "antigravity-cli"
    "antigravity-ide"
    "android-studio"
    "cursor-bin"
    "flutter-bin"
    "visual-studio-code-bin"
)

# List of ASUS specific packages
asus_packages=(
    "vulkan-amdgpu-pro"
    "lib32-vulkan-amdgpu-pro"
    "amdgpu-pro-oglp"
    "lib32-amdgpu-pro-oglp"
    "opencl-headers"
    "amf-amdgpu-pro"
)

# List of AMD GPU and related runtime packages
amd_packages=(
    xf86-video-amdgpu amd-ucode mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
    radeontop libva-mesa-driver lib32-libva-mesa-driver mesa-utils mesa-demos
    vulkan-mesa-layers lib32-mesa-utils lib32-mesa-demos lib32-vulkan-mesa-layers
    glu lib32-glu
    # mesa-vdpau lib32-mesa-vdpau
)

# List of AI/ML and ROCm packages
ai_ml_packages=(
    rocm-llvm rocm-opencl-runtime rocm-opencl-sdk rocm-hip-sdk rocm-ml-libraries
    rocm-openmp hipify-clang rocminfo opencl-headers libclc ocl-icd
    python-pytorch-rocm python-onnxruntime-rocm
)

# ============================================================================
# INSTALLATION
# ============================================================================

# Install base packages
echo ""
echo "Installing base packages..."
install_if_needed "${packages[@]}"

# Initialize Git LFS for the current user
if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
    echo "Initializing Git LFS..."
    git lfs install --skip-repo
fi

if [ "$install_amd" = true ]; then
    echo ""
    echo "Installing AMD GPU drivers and runtimes..."
    install_if_needed "${amd_packages[@]}"

    # Edit GRUB configuration to optimize for AMD
    echo "Editing GRUB configuration..."
    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 amd_pstate=active amd_prefcore=enable"|' /etc/default/grub

    # Regenerate the GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

# Install gaming packages if selected
if [ "$install_gaming" = true ]; then
    echo ""
    echo "Installing gaming packages..."
    if [ -f "$SCRIPT_DIR/apps/gaming.sh" ]; then
        bash "$SCRIPT_DIR/apps/gaming.sh"
    else
        echo "Error: apps/gaming.sh not found."
    fi
fi

# Install AI/ML packages if selected
if [ "$install_aiml" = true ]; then
    echo ""
    echo "Installing AI/ML packages (ROCm, PyTorch, ONNX Runtime)..."
    install_if_needed "${ai_ml_packages[@]}"
fi

# Install X11 tiling-specific packages if selected
if [ "$install_x11" = true ]; then
    echo ""
    echo "Installing X11 tiling-specific packages..."
    if [ -f "$SCRIPT_DIR/desktop/tiling.sh" ]; then
        bash "$SCRIPT_DIR/desktop/tiling.sh"
    else
        echo "Error: desktop/tiling.sh not found."
        exit 1
    fi
fi

# Install KDE Plasma desktop environment if selected
if [ "$install_kde" = true ]; then
    echo ""
    echo "Installing KDE Plasma desktop environment..."
    if [ -f "$SCRIPT_DIR/desktop/kde.sh" ]; then
        bash "$SCRIPT_DIR/desktop/kde.sh"
    else
        echo "Error: desktop/kde.sh not found."
        exit 1
    fi
fi

# Install selected AUR helper(s)
case "$aur_choice" in
1)
    if [ -f "$SCRIPT_DIR/apps/paru.sh" ]; then
        bash "$SCRIPT_DIR/apps/paru.sh"
    fi
    ;;
2)
    if [ -f "$SCRIPT_DIR/apps/yay.sh" ]; then
        bash "$SCRIPT_DIR/apps/yay.sh"
    fi
    ;;
3)
    if [ -f "$SCRIPT_DIR/apps/paru.sh" ]; then
        bash "$SCRIPT_DIR/apps/paru.sh"
    fi
    if [ -f "$SCRIPT_DIR/apps/yay.sh" ]; then
        bash "$SCRIPT_DIR/apps/yay.sh"
    fi
    ;;
*)
    echo "Skipping AUR helper installation."
    ;;
esac

# Install AUR packages
echo ""
echo "Installing AUR packages..."
install_aur_packages "${aur_packages[@]}"

# Install coding-specific AUR packages if selected
if [ "$install_coding" = true ]; then
    echo ""
    echo "Installing coding-specific AUR packages..."
    install_aur_packages "${aur_coding_packages[@]}"
fi

# Install ASUS specific packages if selected
if [ "$install_asus" = true ]; then
    echo ""
    echo "Installing ASUS specific drivers..."
    install_aur_packages "${asus_packages[@]}"
fi

# Install virtualization packages if selected
if [ "$install_virt" = true ]; then
    echo ""
    echo "Installing virtualization packages..."
    if [ -f "$SCRIPT_DIR/virt/vmware-workstation.sh" ]; then
        bash "$SCRIPT_DIR/virt/vmware-workstation.sh"
    else
        echo "Error: virt/vmware-workstation.sh not found."
    fi
fi

# Install Docker if selected
if [ "$install_docker" = true ]; then
    echo ""
    echo "Installing Docker..."
    if [ -f "$SCRIPT_DIR/apps/docker.sh" ]; then
        bash "$SCRIPT_DIR/apps/docker.sh"
    else
        echo "Error: apps/docker.sh not found."
    fi
fi

# Install Burp Suite Professional if selected
if [ "$install_burp" = true ]; then
    echo ""
    echo "Installing Burp Suite Professional..."
    if [ -f "$SCRIPT_DIR/apps/burp/install.sh" ]; then
        bash "$SCRIPT_DIR/apps/burp/install.sh"
    else
        echo "Error: apps/burp/install.sh not found."
    fi
fi

# ============================================================================
# SERVICE CONFIGURATION
# ============================================================================

echo ""
echo "Configuring services..."

# Enable dbus (skip for KDE as it handles this)
if [ "$install_kde" = false ]; then
    if systemctl list-unit-files | grep -q "dbus-broker.service"; then
        systemctl --user enable --now dbus-broker.service
    elif systemctl list-unit-files | grep -q "dbus-daemon.service"; then
        systemctl --user enable --now dbus-daemon.service
    else
        echo "No dbus backend service found, skipping..."
    fi
fi

# Enable SDDM if KDE Plasma is installed
# if [ "$install_kde" = true ] && pacman -Qi sddm &>/dev/null; then
#     if ! systemctl is-enabled sddm.service &>/dev/null; then
#         echo "Enabling SDDM display manager..."
#         sudo systemctl enable --now sddm.service
#     else
#         echo "SDDM is already enabled."
#     fi
# fi

# Start xdg-desktop-portal services (don't enable, they're socket-activated)
systemctl_user_services=(
    "xdg-desktop-portal.service"
    "xdg-desktop-portal-gtk.service"
)

for service in "${systemctl_user_services[@]}"; do
    if systemctl --user list-unit-files | grep -q "$service"; then
        if ! systemctl --user is-active --quiet "$service"; then
            systemctl --user start "$service" 2>/dev/null && echo "Started $service" || true
        fi
    fi
done

# ============================================================================
# DEFAULT APPLICATIONS
# ============================================================================

# Change default shell to zsh if installed
if command -v zsh &>/dev/null; then
    read -rp "Do you want to change your default shell to zsh? (y/n): " change_shell
    if [[ $change_shell =~ ^[Yy]$ ]]; then
        echo "Changing default shell to zsh..."
        chsh -s "$(command -v zsh)" "$USER"
        echo "Default shell changed to zsh. Please log out and log back in for changes to take effect."
    fi
fi

echo ""
echo "=========================================="
echo "Installation completed successfully!"
echo "=========================================="
echo "Please reboot your system for all changes to take effect."
