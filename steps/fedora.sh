#!/usr/bin/env bash
# Fedora step implementations and plan builder

step_fedora_productivity() {
    local apps_str="$1"
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    PROD_APPS="$apps_str" run_module "fedora/apps/productivity.sh"
}

fedora_needs_flatpak() {
    [ "${CFG_DESKTOP:-none}" = "kde" ] && return 0

    if [ "${CFG_CODING:-false}" = true ]; then
        local tool
        for tool in "${CFG_CODING_TOOLS[@]}"; do
            [ "$tool" = "android_studio" ] && return 0
        done
    fi

    if [ "${CFG_PRODUCTIVITY:-false}" = true ]; then
        local app
        for app in "${CFG_PROD_APPS[@]}"; do
            case "$app" in
            zen | obsidian | localsend) return 0 ;;
            esac
        done
    fi

    return 1
}

build_plan_fedora() {
    local distro_dir="${SCRIPT_DIR}/fedora"

    plan_managed_app "docker"
    plan_managed_app "lazydocker"
    plan_managed_app "neovim"
    plan_managed_app "coding"
    plan_managed_app "gaming"
    plan_managed_app "aiml"
    plan_managed_app "productivity"
    plan_managed_app "markitdown"
    plan_managed_app "xdm"

    if [ -f "$distro_dir/system/dnf.sh" ]; then
        plan_add "Configure DNF & Performance Tweaks (fedora/system/dnf.sh)" run_module "fedora/system/dnf.sh"
    fi

    if [ -f "$distro_dir/system/repos.sh" ]; then
        plan_add "Configure System Repositories (fedora/system/repos.sh)" run_module "fedora/system/repos.sh"
    fi

    if fedora_needs_flatpak && [ -f "$distro_dir/system/flatpak.sh" ]; then
        plan_add "Configure Flatpak & Flathub (fedora/system/flatpak.sh)" run_module "fedora/system/flatpak.sh"
    fi

    if [ -f "$distro_dir/system/base.sh" ]; then
        plan_add "Install Base Packages (fedora/system/base.sh)" run_module "fedora/system/base.sh"
    fi

    if [ "$CFG_AMD_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/amd.sh" ]; then
        plan_add "Configure AMD Graphics Drivers (fedora/hardware/gpu/amd.sh)" run_module "fedora/hardware/gpu/amd.sh"
    fi

    if [ "$CFG_INTEL_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/intel.sh" ]; then
        plan_add "Configure Intel Graphics Drivers (fedora/hardware/gpu/intel.sh)" run_module "fedora/hardware/gpu/intel.sh"
    fi

    if [ "$CFG_NVIDIA_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/nvidia.sh" ]; then
        plan_add "Configure NVIDIA Graphics Drivers (fedora/hardware/gpu/nvidia.sh)" run_module "fedora/hardware/gpu/nvidia.sh"
    fi

    if [ "$CFG_ASUS" = true ] && [ -f "$distro_dir/hardware/asus.sh" ]; then
        plan_add "Configure ASUS ROG Tools (fedora/hardware/asus.sh)" run_module "fedora/hardware/asus.sh" "${CFG_ASUS_LIMIT}"
    fi

    if [ "$CFG_DESKTOP" = "kde" ] && [ -f "$distro_dir/desktop/kde.sh" ]; then
        plan_add "Install KDE Plasma Desktop (fedora/desktop/kde.sh)" run_module "fedora/desktop/kde.sh"
    elif [ "$CFG_DESKTOP" = "i3" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
        plan_add "Install i3 Tiling Window Manager (fedora/desktop/tiling.sh i3)" run_module "fedora/desktop/tiling.sh" "i3"
    elif [ "$CFG_DESKTOP" = "bspwm" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
        plan_add "Install BSPWM Tiling Window Manager (fedora/desktop/tiling.sh bspwm)" run_module "fedora/desktop/tiling.sh" "bspwm"
    elif [ "$CFG_DESKTOP" = "tiling" ] || [ "$CFG_DESKTOP" = "both" ]; then
        if [ -f "$distro_dir/desktop/tiling.sh" ]; then
            plan_add "Install X11 Tiling Window Managers (fedora/desktop/tiling.sh both)" run_module "fedora/desktop/tiling.sh" "both"
        fi
    fi

    if [ "$CFG_KVM" = true ] && [ -f "$distro_dir/virt/kvm-qemu.sh" ]; then
        plan_add "Setup KVM, QEMU & virt-manager (fedora/virt/kvm-qemu.sh)" run_module "fedora/virt/kvm-qemu.sh"
    fi

    if [ "$CFG_VMWARE" = true ] && [ -f "$distro_dir/virt/vmware-workstation.sh" ]; then
        plan_add "Install VMware Workstation (fedora/virt/vmware-workstation.sh)" run_module "fedora/virt/vmware-workstation.sh"
    fi

    if [ "$CFG_DOCKER" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
        plan_add "Install Docker Engine (fedora/apps/docker.sh)" run_module "fedora/apps/docker.sh"

        if [ -f "$distro_dir/apps/lazydocker.sh" ]; then
            plan_add "Install lazydocker TUI (fedora/apps/lazydocker.sh)" run_module "fedora/apps/lazydocker.sh"
        fi
    fi

    if [ "$CFG_CODING" = true ] && [ ${#CFG_CODING_TOOLS[@]} -gt 0 ] && [ -f "$distro_dir/apps/coding.sh" ]; then
        plan_add "Install Developer Suite (fedora/apps/coding.sh)" run_module "fedora/apps/coding.sh" "${CFG_CODING_TOOLS[@]}"
    fi

    if [ "$CFG_GAMING" = true ] && [ -f "$distro_dir/apps/gaming.sh" ]; then
        plan_add "Setup Gaming Stack (fedora/apps/gaming.sh)" run_module "fedora/apps/gaming.sh"
    fi

    if [ "$CFG_AIML" = true ] && [ -f "$distro_dir/apps/aiml.sh" ]; then
        plan_add "Install ROCm & AI/ML Acceleration Suite (fedora/apps/aiml.sh)" run_module "fedora/apps/aiml.sh"
    fi

    if [ "$CFG_PRODUCTIVITY" = true ] && [ -f "$distro_dir/apps/productivity.sh" ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        plan_add "Install Productivity Applications (fedora/apps/productivity.sh - ${#CFG_PROD_APPS[@]} apps)" \
            step_fedora_productivity "${CFG_PROD_APPS[*]}"

        local has_xdm=false p
        for p in "${CFG_PROD_APPS[@]}"; do
            if [ "$p" = "xdm" ]; then
                has_xdm=true
                break
            fi
        done
        if [ "$has_xdm" = true ] && [ -f "$distro_dir/apps/xdm.sh" ]; then
            plan_add "Install XDM Download Manager (fedora/apps/xdm.sh)" run_module "fedora/apps/xdm.sh"
        fi
    fi

    append_extra_scripts "$distro_dir" "fedora"

    if [ -f "$distro_dir/system/shell.sh" ]; then
        plan_add "Configure Shell & Terminal Utilities (fedora/system/shell.sh)" run_module "fedora/system/shell.sh"
    fi
}
