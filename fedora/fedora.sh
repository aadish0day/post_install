#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA POST-INSTALLATION (interactive)
# Mirrors arch/arch.sh: asks everything upfront, shows a summary, then runs
# the modular scripts in fedora/system, hardware, desktop, virt and apps.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

prompt_yes_no() {
    local res
    echo ""
    read -rp "$1 (y/n): " res
    [[ "$res" =~ ^[Yy]$ ]]
}

run_module() {
    local script="$SCRIPT_DIR/$1"
    shift
    echo ""
    log "==> fedora/${script#"$SCRIPT_DIR"/} $*"
    if [ -f "$script" ]; then
        bash "$script" "$@"
    else
        err "fedora/${script#"$SCRIPT_DIR"/} not found."
    fi
}

# Keep sudo alive during long operations
if sudo -v; then
    keep_sudo_alive() { while true; do
        sleep 60
        sudo -n true
    done; }
    keep_sudo_alive &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill ${SUDO_KEEP_ALIVE_PID} 2>/dev/null || true' EXIT
fi

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
1) install_kde=true ;;
2) install_x11=true ;;
*) echo "Skipping desktop environment installation." ;;
esac

install_flatpak=false
prompt_yes_no "Do you want to enable Flatpak + Flathub (needed for Android Studio, Zen, LocalSend, Obsidian)?" && install_flatpak=true
install_gaming=false
prompt_yes_no "Do you want to install gaming packages (Wine, Lutris, Steam, GameMode, MangoHud)?" && install_gaming=true
install_asus=false
prompt_yes_no "Do you want to install ASUS ROG tools (asusctl, fan curves, battery limit)?" && install_asus=true
install_kvm=false
prompt_yes_no "Do you want to install KVM/QEMU and virt-manager?" && install_kvm=true
install_vmware=false
prompt_yes_no "Do you want to install VMware Workstation (needs the Broadcom .bundle)?" && install_vmware=true
install_docker=false
prompt_yes_no "Do you want to install Docker?" && install_docker=true
install_amd=false
prompt_yes_no "Do you want to install AMD CPU/GPU drivers (microcode, Mesa, Vulkan, VA-API, amd_pstate)?" && install_amd=true
install_intel=false
prompt_yes_no "Do you want to install Intel CPU/GPU drivers (microcode, Mesa, Vulkan, VA-API)?" && install_intel=true
install_nvidia=false
prompt_yes_no "Do you want to install NVIDIA GPU drivers (RPM Fusion akmod-nvidia)?" && install_nvidia=true
install_aiml=false
prompt_yes_no "Do you want to install AI/ML packages (ROCm, PyTorch ROCm)?" && install_aiml=true
install_coding=false
prompt_yes_no "Do you want to install coding tools (Neovim, VS Code, Cursor, Claude Code, Android Studio, Flutter, Antigravity)?" && install_coding=true
install_productivity=false
prompt_yes_no "Do you want to install productivity apps (AnyDesk, Vesktop, LocalSend, Zen, ani-cli, gallery-dl)?" && install_productivity=true

yn() { [ "$1" = true ] && echo "Yes" || echo "No"; }
de_name="None"
[ "$install_kde" = true ] && de_name="KDE Plasma"
[ "$install_x11" = true ] && de_name="X11 Tiling"

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
echo "Desktop Environment: $de_name"
echo "Flatpak + Flathub: $(yn $install_flatpak)"
echo "Gaming Packages: $(yn $install_gaming)"
echo "ASUS ROG Tools: $(yn $install_asus)"
echo "KVM/QEMU: $(yn $install_kvm)"
echo "VMware Workstation: $(yn $install_vmware)"
echo "Docker: $(yn $install_docker)"
echo "AMD Drivers: $(yn $install_amd)"
echo "Intel Drivers: $(yn $install_intel)"
echo "NVIDIA Drivers: $(yn $install_nvidia)"
echo "AI/ML Packages: $(yn $install_aiml)"
echo "Coding Tools: $(yn $install_coding)"
echo "Productivity Apps: $(yn $install_productivity)"
echo "=========================================="
echo ""
read -rp "Continue with installation? (y/n): " continue_install
if [[ ! $continue_install =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# ============================================================================
# INSTALLATION
# ============================================================================

run_module system/dnf.sh
run_module system/repos.sh
log "Updating the system..."
$SUDO dnf upgrade -y --refresh
[ "$install_flatpak" = true ] && run_module system/flatpak.sh
run_module system/base.sh

[ "$install_amd" = true ] && run_module hardware/gpu/amd.sh
[ "$install_intel" = true ] && run_module hardware/gpu/intel.sh
[ "$install_nvidia" = true ] && run_module hardware/gpu/nvidia.sh
[ "$install_asus" = true ] && run_module hardware/asus.sh

[ "$install_kde" = true ] && run_module desktop/kde.sh
[ "$install_x11" = true ] && run_module desktop/tiling.sh

[ "$install_kvm" = true ] && run_module virt/kvm-qemu.sh
[ "$install_vmware" = true ] && run_module virt/vmware-workstation.sh

[ "$install_docker" = true ] && run_module apps/docker.sh
[ "$install_coding" = true ] && run_module apps/coding.sh
[ "$install_gaming" = true ] && run_module apps/gaming.sh
[ "$install_aiml" = true ] && run_module apps/aiml.sh
[ "$install_productivity" = true ] && run_module apps/productivity.sh

run_module system/shell.sh

echo ""
echo "=========================================="
echo "Installation completed successfully!"
echo "=========================================="
echo "Please reboot your system for all changes to take effect."
