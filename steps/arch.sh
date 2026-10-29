#!/usr/bin/env bash
# Arch Linux step implementations and plan builder

arch_kernel_headers() {
    local kver
    kver="$(uname -r 2>/dev/null || echo "")"
    case "$kver" in
        *-lts*) echo "linux-lts-headers" ;;
        *-zen*) echo "linux-zen-headers" ;;
        *-hardened*) echo "linux-hardened-headers" ;;
        *) echo "linux-headers" ;;
    esac
}

arch_ensure_multilib() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    if [ -f /etc/pacman.conf ] && ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        log "Enabling multilib repository in /etc/pacman.conf..."
        sudo sed -i '/\[multilib\]/,/Include/s/^[#;]//' /etc/pacman.conf
        sudo pacman -Sy
    fi
}

step_arch_aur_helper() {
    local choice="${1:-paru}"
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi

    local primary="$choice"
    local secondary="yay"
    if [ "$primary" = "yay" ]; then
        secondary="paru"
    fi

    log "Attempting to install primary AUR helper ($primary)..."
    if run_module "arch/apps/${primary}.sh"; then
        log "Successfully installed $primary"
        return 0
    fi

    warn "Failed to install $primary. Attempting fallback AUR helper ($secondary)..."
    if run_module "arch/apps/${secondary}.sh"; then
        log "Successfully installed fallback AUR helper $secondary"
        return 0
    fi

    err "Failed to install both $primary and $secondary AUR helpers."
    return 1
}

step_arch_mirrors() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    arch_ensure_multilib
    sudo pacman -Syu --noconfirm
    sudo pacman -S --needed reflector --noconfirm
    timeout 30s sudo reflector --latest 10 --fastest 5 --protocol https \
        --connection-timeout 5 --download-timeout 5 --threads 8 \
        --country India --sort rate --save /etc/pacman.d/mirrorlist ||
        echo "Reflector timed out or failed; keeping existing mirrorlist."
    sudo pacman -Syu --noconfirm
}

step_arch_base_pkgs() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    arch_ensure_multilib
    local base_file="${SCRIPT_DIR:-.}/arch/packages.txt"
    local pkgs=()
    local kheaders
    kheaders="$(arch_kernel_headers)"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line// /}"
        [ -z "$line" ] && continue
        if [ "$line" = "linux-headers" ]; then
            pkgs+=("$kheaders")
        else
            pkgs+=("$line")
        fi
    done <"$base_file"

    if [ ${#pkgs[@]} -gt 0 ]; then
        sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    fi

    if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then
        git lfs install --skip-repo
    fi
}

step_arch_coding() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    local pacman_pkgs=()
    local pkgs=()
    local run_flutter=false
    local -a coding_tools=()
    if [ -n "${CFG_CODING_TOOLS+x}" ]; then
        coding_tools=("${CFG_CODING_TOOLS[@]}")
    fi
    local t
    for t in "${coding_tools[@]}"; do
        case "$t" in
            neovim) pacman_pkgs+=("neovim") ;;
            vscode) pkgs+=("visual-studio-code-bin") ;;
            cursor) pkgs+=("cursor-bin") ;;
            claude_code) pkgs+=("claude-code") ;;
            android_studio) pkgs+=("android-studio") ;;
            flutter)
                pkgs+=("flutter-bin")
                run_flutter=true
                ;;
            antigravity) pkgs+=("antigravity-cli" "antigravity-ide") ;;
        esac
    done

    if [ ${#pacman_pkgs[@]} -gt 0 ]; then
        sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
    fi

    if [ ${#pkgs[@]} -gt 0 ]; then
        local aur
        aur="$(aur_cmd)"
        if [ -z "$aur" ]; then
            echo "Error: no AUR helper found (paru or yay required for coding tools: ${pkgs[*]})" >&2
            return 1
        fi
        "$aur" -S --needed --noconfirm "${pkgs[@]}"
    fi

    if [ "$run_flutter" = true ] && [ -f "${SCRIPT_DIR:-.}/arch/apps/flutter.sh" ]; then
        run_module "arch/apps/flutter.sh"
    fi
}

step_arch_aiml() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    sudo pacman -S --needed --noconfirm \
        rocm-llvm rocm-opencl-runtime rocm-opencl-sdk rocm-hip-sdk rocm-ml-libraries \
        rocm-openmp hipify-clang rocminfo opencl-headers libclc ocl-icd \
        python-pytorch-rocm python-onnxruntime-rocm
}

step_arch_prod_apps() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    local aur
    aur="$(aur_cmd)"
    if [ -z "$aur" ]; then
        echo "Error: no AUR helper found (paru or yay required for productivity apps)" >&2
        return 1
    fi
    local prod_pkgs=()
    local need_thorium=false
    local -a prod_apps=()
    if [ -n "${CFG_PROD_APPS+x}" ]; then
        prod_apps=("${CFG_PROD_APPS[@]}")
    fi
    local p
    for p in "${prod_apps[@]}"; do
        case "$p" in
            thorium) need_thorium=true ;;
            zen) prod_pkgs+=("zen-browser-bin") ;;
            vesktop) prod_pkgs+=("vesktop-bin") ;;
            localsend) prod_pkgs+=("localsend-bin") ;;
            anydesk) prod_pkgs+=("anydesk-bin") ;;
            obsidian) prod_pkgs+=("obsidian") ;;
            markitdown) prod_pkgs+=("markitdown-bin") ;;
            gallery_dl) prod_pkgs+=("gallery-dl-bin") ;;
            ani_cli) prod_pkgs+=("ani-cli") ;;
            advcpmv) prod_pkgs+=("advcpmv") ;;
            libreoffice) prod_pkgs+=("libreoffice-fresh") ;;
        esac
    done

    if [ "$need_thorium" = true ]; then
        prod_pkgs+=("$(thorium_pkg)")
    fi

    if [ ${#prod_pkgs[@]} -gt 0 ]; then
        "$aur" -S --needed --noconfirm "${prod_pkgs[@]}"
    fi
}

step_arch_services_shell() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    sudo systemctl enable --now rtkit-daemon.service 2>/dev/null || true
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files 2>/dev/null | grep -q "$s"; then
            systemctl --user start "$s" 2>/dev/null || true
        fi
    done
    local zsh_bin
    zsh_bin="$(command -v zsh 2>/dev/null || echo '')"
    if [ -n "$zsh_bin" ] && [ "${SHELL:-}" != "$zsh_bin" ]; then
        chsh -s "$zsh_bin" "${USER:-$(id -un)}" 2>/dev/null || true
    fi
}

arch_needs_aur() {
    # If any coding tools requiring AUR are selected
    if [ "${CFG_CODING:-false}" = true ] && [ -n "${CFG_CODING_TOOLS+x}" ] && [ ${#CFG_CODING_TOOLS[@]} -gt 0 ]; then
        local tool
        for tool in "${CFG_CODING_TOOLS[@]}"; do
            case "$tool" in
                vscode | cursor | claude_code | android_studio | flutter | antigravity) return 0 ;;
            esac
        done
    fi

    # If any productivity apps are selected (all are AUR in Arch)
    if [ "${CFG_PRODUCTIVITY:-false}" = true ] && [ -n "${CFG_PROD_APPS+x}" ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        return 0
    fi

    # If Burp Suite is selected
    [ "${CFG_SECURITY_BURP:-false}" = true ] && return 0

    return 1
}

build_plan_arch() {
    local distro_dir="${SCRIPT_DIR:-.}/arch"

    # Register managed apps for append_extra_scripts
    plan_managed_app "docker"
    plan_managed_app "gaming"
    plan_managed_app "paru"
    plan_managed_app "yay"
    plan_managed_app "flutter"
    plan_managed_app "burp"
    plan_managed_app "xdm"

    if [ "${CFG_MIRRORS:-false}" = true ]; then
        plan_add "Optimize Mirrorlist (Reflector India)" step_arch_mirrors
    fi

    plan_add "Install Arch Base Packages & Utilities" step_arch_base_pkgs

    local effective_aur="${CFG_AUR:-none}"
    if [ "$effective_aur" = "none" ] && arch_needs_aur; then
        effective_aur="paru"
    fi

    if [ "$effective_aur" = "both" ]; then
        if [ -f "$distro_dir/apps/paru.sh" ]; then
            plan_add "Install Paru AUR Helper (arch/apps/paru.sh)" run_module "arch/apps/paru.sh"
        fi
        if [ -f "$distro_dir/apps/yay.sh" ]; then
            plan_add "Install Yay AUR Helper (arch/apps/yay.sh)" run_module "arch/apps/yay.sh"
        fi
    elif [ "$effective_aur" = "paru" ]; then
        plan_add "Install Paru AUR Helper (arch/apps/paru.sh)" step_arch_aur_helper "paru"
    elif [ "$effective_aur" = "yay" ]; then
        plan_add "Install Yay AUR Helper (arch/apps/yay.sh)" step_arch_aur_helper "yay"
    fi

    if [ "${CFG_AMD_GPU:-false}" = true ] && [ -f "$distro_dir/hardware/gpu/amd.sh" ]; then
        if [ "${CFG_AMD_PRO:-false}" = true ]; then
            plan_add "AMD CPU/GPU Drivers & P-State Optimization (arch/hardware/gpu/amd.sh)" run_module "arch/hardware/gpu/amd.sh" "--pro"
        else
            plan_add "AMD CPU/GPU Drivers & P-State Optimization (arch/hardware/gpu/amd.sh)" run_module "arch/hardware/gpu/amd.sh"
        fi
    fi

    if [ "${CFG_INTEL_GPU:-false}" = true ] && [ -f "$distro_dir/hardware/gpu/intel.sh" ]; then
        plan_add "Intel CPU/GPU Drivers (arch/hardware/gpu/intel.sh)" run_module "arch/hardware/gpu/intel.sh"
    fi

    if [ "${CFG_NVIDIA_GPU:-false}" = true ] && [ -f "$distro_dir/hardware/gpu/nvidia.sh" ]; then
        plan_add "NVIDIA GPU Drivers (arch/hardware/gpu/nvidia.sh)" run_module "arch/hardware/gpu/nvidia.sh"
    fi

    if [ "${CFG_ASUS:-false}" = true ] && [ -f "$distro_dir/hardware/asus.sh" ]; then
        plan_add "Configure ASUS ROG & Power Tooling (arch/hardware/asus.sh)" run_module "arch/hardware/asus.sh" "${CFG_ASUS_LIMIT:-80}"
    fi

    if [ "${CFG_DESKTOP:-none}" = "kde" ] && [ -f "$distro_dir/desktop/kde.sh" ]; then
        plan_add "Install KDE Plasma Desktop (arch/desktop/kde.sh)" run_module "arch/desktop/kde.sh"
    elif [ "${CFG_DESKTOP:-none}" = "i3" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
        plan_add "Install i3 Tiling Window Manager (arch/desktop/tiling.sh i3)" run_module "arch/desktop/tiling.sh" "i3"
    elif [ "${CFG_DESKTOP:-none}" = "bspwm" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
        plan_add "Install BSPWM Tiling Window Manager (arch/desktop/tiling.sh bspwm)" run_module "arch/desktop/tiling.sh" "bspwm"
    elif [ "${CFG_DESKTOP:-none}" = "tiling" ] || [ "${CFG_DESKTOP:-none}" = "both" ]; then
        if [ -f "$distro_dir/desktop/tiling.sh" ]; then
            plan_add "Install X11 Tiling Window Managers (arch/desktop/tiling.sh both)" run_module "arch/desktop/tiling.sh" "both"
        fi
    fi

    if [ "${CFG_KVM:-false}" = true ] && [ -f "$distro_dir/virt/kvm-qemu.sh" ]; then
        plan_add "Setup KVM, QEMU & virt-manager (arch/virt/kvm-qemu.sh)" run_module "arch/virt/kvm-qemu.sh"
    fi

    if [ "${CFG_VMWARE:-false}" = true ] && [ -f "$distro_dir/virt/vmware-workstation.sh" ]; then
        plan_add "Install VMware Workstation (arch/virt/vmware-workstation.sh)" run_module "arch/virt/vmware-workstation.sh"
    fi

    if [ "${CFG_DOCKER:-false}" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
        plan_add "Install Docker Engine & Buildx (arch/apps/docker.sh)" run_module "arch/apps/docker.sh"
    fi

    local -a coding_tools=()
    if [ -n "${CFG_CODING_TOOLS+x}" ]; then
        coding_tools=("${CFG_CODING_TOOLS[@]}")
    fi
    if [ "${CFG_CODING:-false}" = true ] && [ ${#coding_tools[@]} -gt 0 ]; then
        plan_add "Install Developer & Coding Suite (${#coding_tools[@]} tools)" step_arch_coding
    fi

    if [ "${CFG_SECURITY_BURP:-false}" = true ] && [ -f "$distro_dir/apps/burp/install.sh" ]; then
        plan_add "Setup Burp Suite Professional (arch/apps/burp/install.sh)" run_module "arch/apps/burp/install.sh"
    fi

    if [ "${CFG_GAMING:-false}" = true ] && [ -f "$distro_dir/apps/gaming.sh" ]; then
        plan_add "Setup Gaming Stack (arch/apps/gaming.sh)" run_module "arch/apps/gaming.sh"
    fi

    if [ "${CFG_AIML:-false}" = true ]; then
        plan_add "Install ROCm & AI/ML Acceleration Suite" step_arch_aiml
    fi

    local -a prod_apps=()
    if [ -n "${CFG_PROD_APPS+x}" ]; then
        prod_apps=("${CFG_PROD_APPS[@]}")
    fi
    if [ "${CFG_PRODUCTIVITY:-false}" = true ] && [ ${#prod_apps[@]} -gt 0 ]; then
        plan_add "Install Essential AUR Productivity Tools (${#prod_apps[@]} apps)" step_arch_prod_apps

        local has_xdm=false p
        for p in "${prod_apps[@]}"; do
            if [ "$p" = "xdm" ]; then
                has_xdm=true
                break
            fi
        done
        if [ "$has_xdm" = true ] && [ -f "$distro_dir/apps/xdm.sh" ]; then
            plan_add "Install XDM Download Manager (arch/apps/xdm.sh)" run_module "arch/apps/xdm.sh"
        fi
    fi

    append_extra_scripts "$distro_dir" "arch"

    plan_add "Configure Services & Default Shell" step_arch_services_shell
}
