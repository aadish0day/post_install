#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEBIAN / UBUNTU POST-INSTALL (interactive master script, mirrors arch/arch.sh)
# Runs the modular scripts in system/, hardware/, desktop/, virt/ and apps/.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
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
    log "==> $(basename "$(dirname "$script")")/$(basename "$script") $*"
    if [ ! -f "$script" ]; then
        err "Missing module: $script"
        return 1
    fi
    bash "$script" "$@"
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
case "$de_choice" in
1) desktop="kde" ;;
2) desktop="tiling" ;;
*) desktop="none" ;;
esac

install_pacstall=false
prompt_yes_no "Install Pacstall (AUR-like package manager, used for apps not in apt)?" && install_pacstall=true
install_flatpak=false
prompt_yes_no "Install Flatpak with Flathub?" && install_flatpak=true
install_gaming=false
prompt_yes_no "Install gaming packages (Wine, Steam, Lutris, GameMode, MangoHud)?" && install_gaming=true
install_asus=false
prompt_yes_no "Install ASUS ROG tools (asusctl built from source, fan curves, battery limit)?" && install_asus=true
install_kvm=false
prompt_yes_no "Install KVM/QEMU and virt-manager?" && install_kvm=true
install_vmware=false
prompt_yes_no "Install VMware Workstation (needs the Broadcom .bundle in ~/Downloads)?" && install_vmware=true
install_docker=false
prompt_yes_no "Install Docker CE?" && install_docker=true
install_amd=false
prompt_yes_no "Install AMD CPU/GPU drivers (microcode, Mesa, Vulkan, amd_pstate)?" && install_amd=true
install_intel=false
prompt_yes_no "Install Intel CPU/GPU drivers (microcode, Mesa, Vulkan, VA-API)?" && install_intel=true
install_nvidia=false
prompt_yes_no "Install NVIDIA GPU drivers (nvidia-open-kernel-dkms)?" && install_nvidia=true
install_aiml=false
prompt_yes_no "Install AI/ML packages (ROCm runtime, PyTorch ROCm venv)?" && install_aiml=true
install_coding=false
prompt_yes_no "Install coding tools (Neovim, VS Code, Cursor, Claude Code, Android Studio, Flutter, Antigravity)?" && install_coding=true
install_productivity=false
prompt_yes_no "Install productivity apps (AnyDesk, Thorium, Zen, Vesktop, Obsidian, LocalSend, ani-cli, gallery-dl, MarkItDown)?" && install_productivity=true

yn() { [ "$1" = true ] && echo "Yes" || echo "No"; }

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
echo "Desktop Environment:   $desktop"
echo "Pacstall:              $(yn "$install_pacstall")"
echo "Flatpak:               $(yn "$install_flatpak")"
echo "Gaming Packages:       $(yn "$install_gaming")"
echo "ASUS ROG Tools:        $(yn "$install_asus")"
echo "KVM/QEMU:              $(yn "$install_kvm")"
echo "VMware Workstation:    $(yn "$install_vmware")"
echo "Docker:                $(yn "$install_docker")"
echo "AMD Drivers:           $(yn "$install_amd")"
echo "Intel Drivers:         $(yn "$install_intel")"
echo "NVIDIA Drivers:        $(yn "$install_nvidia")"
echo "AI/ML Packages:        $(yn "$install_aiml")"
echo "Coding Tools:          $(yn "$install_coding")"
echo "Productivity Apps:     $(yn "$install_productivity")"
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

run_module system/repos.sh
[ "$install_pacstall" = true ] && run_module system/pacstall.sh
[ "$install_flatpak" = true ] && run_module system/flatpak.sh
run_module system/base.sh

[ "$install_amd" = true ] && run_module hardware/gpu/amd.sh
[ "$install_intel" = true ] && run_module hardware/gpu/intel.sh
[ "$install_nvidia" = true ] && run_module hardware/gpu/nvidia.sh
[ "$install_asus" = true ] && run_module hardware/asus.sh

case "$desktop" in
kde) run_module desktop/kde.sh ;;
tiling) run_module desktop/tiling.sh ;;
esac

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
