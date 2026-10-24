#!/usr/bin/env bash
# Data-driven main menu for post_install TUI.
# Rows format: tag|label|kind|var|distros|badge_fn
# kind = toggle | choice | multi | info | action
# label starting with @ is resolved by menu_label_for.

MENU_ROWS=(
    "distro|Distribution / Target OS|choice|TARGET_DISTRO|arch debian fedora kali termux|menu_badge_distro"
    "desktop|Desktop Environment|choice|CFG_DESKTOP|arch debian fedora|menu_badge_desktop"
    "hardware|@hardware|multi|CFG_HARDWARE|arch debian fedora|menu_badge_hardware"
    "virt|@virt|multi|CFG_VIRT|arch debian fedora|menu_badge_virt"
    "docker|@docker|toggle|CFG_DOCKER|arch debian fedora kali|menu_badge_docker"
    "coding|@coding|multi|CFG_CODING_TOOLS|arch debian fedora|menu_badge_coding"
    "burp|Burp Suite Professional|toggle|CFG_SECURITY_BURP|arch kali|menu_badge_burp"
    "gaming|@gaming|toggle|CFG_GAMING|arch debian fedora|menu_badge_gaming"
    "aiml|AI / ML Acceleration (ROCm)|toggle|CFG_AIML|arch debian fedora|menu_badge_aiml"
    "prod|@prod|multi|CFG_PROD_APPS|arch debian fedora|menu_badge_prod"
    "aur|AUR Helper Selection|choice|CFG_AUR|arch|menu_badge_aur"
    "mirrors|Mirror Optimization (Reflector India)|toggle|CFG_MIRRORS|arch|menu_badge_mirrors"
    "kali_meta|Kali Metapackages|choice|CFG_KALI_META|kali|menu_badge_kali_meta"
    "wifi|Realtek WiFi Driver (RTL8821AU)|toggle|CFG_KALI_WIFI|kali|menu_badge_wifi"
    "advcpmv|Advanced Copy (advcpmv progress bar)|toggle|CFG_ADVCPMV|kali|menu_badge_advcpmv"
    "termux_core|Termux Environment Setup|info||termux|menu_badge_termux_core"
    "fonts|JetBrains Mono Nerd Font|toggle|CFG_FONTS|termux|menu_badge_fonts"
    "install|--> Install|action||arch debian fedora kali termux|menu_badge_install"
    "abort|--> Abort|action||arch debian fedora kali termux|menu_badge_abort"
)

# Per-distro row order matching main
declare -A MENU_ORDER=(
    [arch]="distro desktop hardware virt docker coding burp gaming aiml prod aur mirrors install abort"
    [debian]="distro desktop hardware virt docker coding gaming aiml prod install abort"
    [fedora]="distro desktop hardware virt docker coding gaming aiml prod install abort"
    [kali]="distro burp kali_meta wifi docker advcpmv install abort"
    [termux]="distro termux_core fonts install abort"
)

# Catalogs: tag|label|var_or_target|guard
CATALOG_HARDWARE=(
    "asus|ASUS ROG Tools & Fan Curves ({D}/hardware/asus.sh)|CFG_ASUS|"
    "amd|AMD CPU/GPU Drivers & Optimization ({D}/hardware/gpu/amd.sh)|CFG_AMD_GPU|"
    "intel|Intel CPU/GPU Drivers ({D}/hardware/gpu/intel.sh)|CFG_INTEL_GPU|"
    "nvidia|NVIDIA GPU Drivers ({D}/hardware/gpu/nvidia.sh)|CFG_NVIDIA_GPU|"
)
CATALOG_VIRT=(
    "kvm|KVM / QEMU & virt-manager (libvirtd network)|CFG_KVM|"
    "vmware|VMware Workstation Host & Kernel Modules|CFG_VMWARE|"
)
CATALOG_CODING=(
    "neovim|Neovim Modern Text Editor|CFG_CODING_TOOLS|all"
    "vscode|Visual Studio Code|CFG_CODING_TOOLS|"
    "cursor|Cursor AI Code Editor|CFG_CODING_TOOLS|"
    "claude_code|Claude Code CLI|CFG_CODING_TOOLS|"
    "android_studio|Android Studio|CFG_CODING_TOOLS|"
    "flutter|Flutter SDK & Android Integration|CFG_CODING_TOOLS|"
    "antigravity|Antigravity CLI & IDE|CFG_CODING_TOOLS|"
)
CATALOG_PROD=(
    "thorium|Thorium Browser (Optimized Chromium fork)|CFG_PROD_APPS|"
    "zen|Zen Browser (Gecko privacy browser)|CFG_PROD_APPS|"
    "vesktop|Vesktop Discord Client (Wayland & Vencord)|CFG_PROD_APPS|"
    "localsend|LocalSend (AirDrop alternative)|CFG_PROD_APPS|"
    "anydesk|AnyDesk (Remote desktop client)|CFG_PROD_APPS|"
    "obsidian|Obsidian (Markdown notes & knowledge base)|CFG_PROD_APPS|"
    "markitdown|MarkItDown (Document converter)|CFG_PROD_APPS|"
    "gallery_dl|gallery-dl (Image batch downloader)|CFG_PROD_APPS|"
    "ani_cli|ani-cli (Anime streaming CLI)|CFG_PROD_APPS|"
    "libreoffice|LibreOffice (Office productivity suite)|CFG_PROD_APPS|debian"
    "xdm|XDM (Xtreme Download Manager)|CFG_PROD_APPS|"
    "advcpmv|advcpmv (cp/mv with progress bars)|CFG_PROD_APPS|arch debian"
)

CHECKLIST_PROMPT="Toggle components to configure (select ALL/NONE to bulk toggle):\n\n[j/k]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm"

menu_lookup() {
    local want="$1" row
    for row in "${MENU_ROWS[@]}"; do
        IFS='|' read -r ROW_TAG ROW_LABEL ROW_KIND ROW_VAR ROW_DISTROS ROW_BADGE <<<"$row"
        if [ "$ROW_TAG" = "$want" ]; then
            return 0
        fi
    done
    return 1
}

menu_visible() {
    case " $1 " in
    *" $TARGET_DISTRO "*) return 0 ;;
    *) return 1 ;;
    esac
}

menu_label_for() {
    local label="$1"
    case "$label" in
    @hardware)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Hardware & Drivers (%s/hardware/)' "$TARGET_DISTRO"
        else
            printf 'Hardware & Drivers'
        fi
        ;;
    @virt)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Virtualization (%s/virt/)' "$TARGET_DISTRO"
        else
            printf 'Virtualization'
        fi
        ;;
    @docker)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Docker Engine & Buildx'
        elif [ "$TARGET_DISTRO" = "kali" ]; then
            printf 'Docker CE Engine'
        else
            printf 'Docker Engine'
        fi
        ;;
    @coding)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Developer Tools (AUR)'
        else
            printf 'Developer Suite'
        fi
        ;;
    @gaming)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Gaming Stack & Wine'
        else
            printf 'Gaming Stack'
        fi
        ;;
    @prod)
        if [ "$TARGET_DISTRO" = "arch" ]; then
            printf 'Productivity & Browsers (AUR)'
        else
            printf 'Productivity Applications'
        fi
        ;;
    *) printf '%s' "$label" ;;
    esac
}

menu_badge_distro() {
    printf '[%s] %s' "${TARGET_DISTRO^^}" "$DISTRO_NAME"
}

menu_badge_desktop() {
    case "$CFG_DESKTOP" in
    kde) printf '[KDE]' ;;
    i3) printf '[i3]' ;;
    bspwm) printf '[BSPWM]' ;;
    both | tiling) printf '[i3 + BSPWM]' ;;
    none | *) printf '[NONE]' ;;
    esac
}

menu_badge_hardware() {
    local hw_tags=()
    [ "$CFG_ASUS" = true ] && hw_tags+=("ASUS (${CFG_ASUS_LIMIT}%)")
    if [ "$CFG_AMD_GPU" = true ]; then
        if [ "$TARGET_DISTRO" = "arch" ] && [ "$CFG_AMD_PRO" = true ]; then
            hw_tags+=("AMD + Pro")
        else
            hw_tags+=("AMD")
        fi
    fi
    [ "$CFG_INTEL_GPU" = true ] && hw_tags+=("Intel")
    [ "$CFG_NVIDIA_GPU" = true ] && hw_tags+=("NVIDIA")
    [ "$CFG_TOUCHPAD" = true ] && hw_tags+=("Touchpad")
    if [ ${#hw_tags[@]} -gt 0 ]; then
        local hw_str="" tag
        for tag in "${hw_tags[@]}"; do
            [ -n "$hw_str" ] && hw_str+=", "
            hw_str+="$tag"
        done
        printf '[%s]' "$hw_str"
    else
        printf '[None]'
    fi
}

menu_badge_virt() {
    local virt_tags=()
    [ "$CFG_KVM" = true ] && virt_tags+=("KVM/QEMU")
    [ "$CFG_VMWARE" = true ] && virt_tags+=("VMware")
    if [ ${#virt_tags[@]} -gt 0 ]; then
        local virt_str="" tag
        for tag in "${virt_tags[@]}"; do
            [ -n "$virt_str" ] && virt_str+=", "
            virt_str+="$tag"
        done
        printf '[%s]' "$virt_str"
    else
        printf '[None]'
    fi
}

menu_badge_docker() {
    if [ "$CFG_DOCKER" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_coding() {
    if [ "$CFG_CODING" = true ]; then
        printf '[%d tools]' "${#CFG_CODING_TOOLS[@]}"
    else
        printf '[No]'
    fi
}

menu_badge_burp() {
    if [ "$CFG_SECURITY_BURP" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_gaming() {
    if [ "$CFG_GAMING" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_aiml() {
    if [ "$CFG_AIML" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_prod() {
    if [ "$CFG_PRODUCTIVITY" = true ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        printf '[%d apps]' "${#CFG_PROD_APPS[@]}"
    else
        printf '[No]'
    fi
}

menu_badge_aur() {
    printf '[%s]' "${CFG_AUR^^}"
}

menu_badge_mirrors() {
    if [ "$CFG_MIRRORS" = true ]; then printf '[Yes (India)]'; else printf '[No]'; fi
}

menu_badge_kali_meta() {
    printf '[%s]' "$CFG_KALI_META"
}

menu_badge_wifi() {
    if [ "$CFG_KALI_WIFI" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_advcpmv() {
    if [ "${CFG_ADVCPMV:-false}" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_termux_core() {
    printf '[Yes]'
}

menu_badge_fonts() {
    if [ "$CFG_FONTS" = true ]; then printf '[Yes]'; else printf '[No]'; fi
}

menu_badge_install() {
    printf '[Start post-installation]'
}

menu_badge_abort() {
    printf '[Exit installer]'
}

menu_catalog_visible() {
    local guard="$1"
    [ -z "$guard" ] && return 0
    case "$guard" in
    all) return 0 ;;
    arch) [ "$TARGET_DISTRO" = "arch" ] ;;
    nonarch) [ "$TARGET_DISTRO" != "arch" ] ;;
    *)
        [[ " $guard " =~ [[:space:]]${TARGET_DISTRO}[[:space:]] ]]
        ;;
    esac
}

menu_choice_distro() {
    local choice
    choice=$(ui_menu "Select Distribution / Target OS" "Select active distribution workspace folder:" "$TARGET_DISTRO" \
        "arch" "Arch Linux (arch/ modular folder)" \
        "debian" "Debian / Ubuntu (debian/ modular folder)" \
        "fedora" "Fedora (fedora/ modular folder)" \
        "kali" "Kali Linux (kali/ modular folder)" \
        "termux" "Termux (termux/ modular folder)") || return 0
    if [ -n "$choice" ] && [ "$choice" != "$TARGET_DISTRO" ]; then
        TARGET_DISTRO="$choice"
        detect_system
        set_distro_defaults
    fi
}

menu_choice_desktop() {
    local choice
    choice=$(ui_menu "Desktop Environment (${TARGET_DISTRO}/desktop/)" "Select desktop environment for ${DISTRO_NAME}:" "$CFG_DESKTOP" \
        "kde" "KDE Plasma Desktop (${TARGET_DISTRO}/desktop/kde.sh)" \
        "i3" "i3 Window Manager (${TARGET_DISTRO}/desktop/tiling.sh i3)" \
        "bspwm" "BSPWM + sxhkd (${TARGET_DISTRO}/desktop/tiling.sh bspwm)" \
        "both" "Both i3 & BSPWM (${TARGET_DISTRO}/desktop/tiling.sh both)" \
        "none" "None / Headless (Skip desktop setup)") || return 0
    if [ -n "$choice" ]; then
        CFG_DESKTOP="$choice"
    fi
}

menu_choice_aur() {
    local choice
    choice=$(ui_menu "AUR Helper Selection (arch/apps/)" "Choose the AUR helper to install:" "$CFG_AUR" \
        "paru" "Paru (Modern Rust-based AUR helper, Recommended)" \
        "yay" "Yay (Classic Go-based AUR helper)" \
        "both" "Both (Install Paru & Yay side-by-side)" \
        "none" "None (Skip AUR helper installation)") || return 0
    if [ -n "$choice" ]; then
        CFG_AUR="$choice"
    fi
}

menu_choice_kali_meta() {
    local choice
    choice=$(ui_menu "Kali Metapackages" "Select suite:" "$CFG_KALI_META" \
        "large" "kali-linux-large (Recommended)" \
        "everything" "kali-linux-everything" \
        "default" "kali-linux-default") || return 0
    if [ -n "$choice" ]; then
        CFG_KALI_META="$choice"
    fi
}

menu_multi_hardware() {
    local items=() entry tag label var guard state
    for entry in "${CATALOG_HARDWARE[@]}"; do
        IFS='|' read -r tag label var guard <<<"$entry"
        menu_catalog_visible "$guard" || continue
        label="${label//\{D\}/$TARGET_DISTRO}"
        state=OFF
        [ "${!var}" = true ] && state=ON
        items+=("$tag" "$label" "$state")
    done

    local sel=""
    sel=$(ui_checklist "Hardware & Drivers (${TARGET_DISTRO}/hardware/)" "$CHECKLIST_PROMPT" "${items[@]}") || return 0

    for entry in "${CATALOG_HARDWARE[@]}"; do
        IFS='|' read -r tag label var guard <<<"$entry"
        printf -v "$var" '%s' false
    done
    while IFS= read -r tag; do
        case "$tag" in
        asus) CFG_ASUS=true ;;
        amd) CFG_AMD_GPU=true ;;
        intel) CFG_INTEL_GPU=true ;;
        nvidia) CFG_NVIDIA_GPU=true ;;
        esac
    done <<<"$sel"

    # 1. AMD Pro sub-prompt (Arch only)
    if [ "$CFG_AMD_GPU" = true ] && [ "$TARGET_DISTRO" = "arch" ]; then
        local pro_default="no"
        [ "$CFG_AMD_PRO" = true ] && pro_default="yes"
        local pro_choice
        pro_choice=$(ui_menu "Install AMD Pro Packages? (arch/hardware/gpu/amd.sh --pro)" \
            "Install proprietary AMD Pro components (AMF, OpenCL, OGLP from AUR)?" "$pro_default" \
            "no" "No  - Open-source Mesa stack only (Recommended)" \
            "yes" "Yes - Also install AMD Pro AUR packages (AMF, OpenCL, OGLP)") || pro_choice="$pro_default"
        if [ "$pro_choice" = "yes" ]; then
            CFG_AMD_PRO=true
        else
            CFG_AMD_PRO=false
        fi
    else
        CFG_AMD_PRO=false
    fi

    # 2. ASUS battery limit sub-prompt (60/80/85/100/custom with 50-100 clamp)
    if [ "$CFG_ASUS" = true ]; then
        ui_restore_cursor
        local limit_choice
        limit_choice=$(ui_menu "ASUS Battery Charge Limit" \
            "Select battery charge threshold limit (prolongs battery health):\n\nCurrent threshold: ${CFG_ASUS_LIMIT}%" \
            "$CFG_ASUS_LIMIT" \
            "85" "85% - Balanced ROG default (Recommended)" \
            "80" "80% - Extended battery longevity" \
            "60" "60% - Maximum lifespan (Stationary / Desk use)" \
            "100" "100% - Full capacity (Maximum mobile runtime)" \
            "custom" "Custom - Enter specific percentage (50-100)...") || limit_choice="$CFG_ASUS_LIMIT"

        if [ "$limit_choice" = "custom" ]; then
            local limit_str=""
            ui_restore_cursor
            limit_str=$(ui_input "Custom ASUS Battery Limit" "Enter battery charge threshold percentage (50-100):" "$CFG_ASUS_LIMIT") || limit_str="$CFG_ASUS_LIMIT"
            if [ -n "$limit_str" ] && [[ "$limit_str" =~ ^[0-9]+$ ]]; then
                [ "$limit_str" -lt 50 ] && limit_str=50
                [ "$limit_str" -gt 100 ] && limit_str=100
                CFG_ASUS_LIMIT="$limit_str"
            fi
        elif [ -n "$limit_choice" ] && [[ "$limit_choice" =~ ^[0-9]+$ ]]; then
            CFG_ASUS_LIMIT="$limit_choice"
        fi
    fi
}

menu_multi_virt() {
    local items=() entry tag label var guard state
    for entry in "${CATALOG_VIRT[@]}"; do
        IFS='|' read -r tag label var guard <<<"$entry"
        menu_catalog_visible "$guard" || continue
        state=OFF
        [ "${!var}" = true ] && state=ON
        items+=("$tag" "$label" "$state")
    done

    local sel=""
    sel=$(ui_checklist "Virtualization Setup (${TARGET_DISTRO}/virt/)" "$CHECKLIST_PROMPT" "${items[@]}") || return 0

    for entry in "${CATALOG_VIRT[@]}"; do
        IFS='|' read -r tag label var guard <<<"$entry"
        printf -v "$var" '%s' false
    done
    while IFS= read -r tag; do
        case "$tag" in
        kvm) CFG_KVM=true ;;
        vmware) CFG_VMWARE=true ;;
        esac
    done <<<"$sel"
}

menu_multi_coding() {
    local items=() entry tag label guard state t
    for entry in "${CATALOG_CODING[@]}"; do
        IFS='|' read -r tag label _var guard <<<"$entry"
        menu_catalog_visible "$guard" || continue
        state=OFF
        for t in "${CFG_CODING_TOOLS[@]}"; do
            if [ "$t" = "$tag" ]; then
                state=ON
                break
            fi
        done
        items+=("$tag" "$label" "$state")
    done

    local sel=""
    sel=$(ui_checklist "Developer & Coding Suite" "$CHECKLIST_PROMPT" "${items[@]}") || return 0

    CFG_CODING_TOOLS=()
    while IFS= read -r tag; do
        case "$tag" in
        neovim | vscode | cursor | claude_code | android_studio | flutter | antigravity)
            CFG_CODING_TOOLS+=("$tag")
            ;;
        esac
    done <<<"$sel"

    if [ ${#CFG_CODING_TOOLS[@]} -gt 0 ]; then
        CFG_CODING=true
    else
        CFG_CODING=false
    fi
}

menu_multi_prod() {
    local items=() entry tag label guard state p
    for entry in "${CATALOG_PROD[@]}"; do
        IFS='|' read -r tag label _var guard <<<"$entry"
        menu_catalog_visible "$guard" || continue
        state=OFF
        for p in "${CFG_PROD_APPS[@]}"; do
            if [ "$p" = "$tag" ]; then
                state=ON
                break
            fi
        done
        items+=("$tag" "$label" "$state")
    done

    local sel=""
    sel=$(ui_checklist "Productivity & Browsers" "$CHECKLIST_PROMPT" "${items[@]}") || return 0

    CFG_PROD_APPS=()
    while IFS= read -r tag; do
        case "$tag" in
        thorium | zen | vesktop | localsend | anydesk | obsidian | markitdown | gallery_dl | ani_cli | xdm | advcpmv | libreoffice)
            CFG_PROD_APPS+=("$tag")
            ;;
        esac
    done <<<"$sel"

    if [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        CFG_PRODUCTIVITY=true
    else
        CFG_PRODUCTIVITY=false
    fi
}

menu_activate() {
    local choice="$1"
    menu_lookup "$choice" || return 0
    case "$ROW_KIND" in
    toggle)
        local cur="${!ROW_VAR}"
        if [ "$cur" = true ]; then
            printf -v "$ROW_VAR" '%s' false
        else
            printf -v "$ROW_VAR" '%s' true
        fi
        ;;
    choice) "menu_choice_$ROW_TAG" ;;
    multi) "menu_multi_$ROW_TAG" ;;
    info | action) : ;;
    esac
}

run_tui() {
    ui_ensure_dialog
    ui_detect

    if [ "$UI_TOOL" = "none" ]; then
        log_warn "Neither 'dialog' nor 'whiptail' found. Falling back to CLI mode."
        run_cli_interactive
        return
    fi

    ui_init
    ui_restore_cursor

    local current_item="distro"

    while true; do
        local menu_title="Post-Installation Automation Suite (Archinstall TUI)"
        local menu_prompt="Host: ${SYS_HOSTNAME} (${CPU_VENDOR}) | OS Folder: ./${TARGET_DISTRO}/ | User: ${SYS_USER}\n\n[j/k]=Navigate  [ENTER]=Select/Toggle  [h/l]=Buttons"

        local menu_items=()
        local tag label badge formatted
        for tag in ${MENU_ORDER[$TARGET_DISTRO]:-}; do
            menu_lookup "$tag" || continue
            menu_visible "$ROW_DISTROS" || continue
            label="$(menu_label_for "$ROW_LABEL")"
            badge="$("$ROW_BADGE")"
            printf -v formatted "%-42s %s" "$label" "$badge"
            menu_items+=("$ROW_TAG" "$formatted")
        done

        local item_exists=false m
        for ((m = 0; m < ${#menu_items[@]} && m < 100; m += 2)); do
            if [ "${menu_items[m]}" = "$current_item" ]; then
                item_exists=true
                break
            fi
        done
        if [ "$item_exists" = false ]; then
            current_item="distro"
        fi

        local choice=""
        choice=$(ui_menu "$menu_title" "$menu_prompt" "$current_item" "${menu_items[@]}") || choice="abort"

        if [ -n "$choice" ] && [ "$choice" != "abort" ] && [ "$choice" != "install" ]; then
            current_item="$choice"
        fi

        case "$choice" in
        install)
            build_plan
            local plan_msg="Ready to execute ./${TARGET_DISTRO}/ post-installation plan (${#PLAN_TITLES[@]} steps).\n\nTarget OS: ${DISTRO_NAME}\nSession Log: ${LOG_FILE}\n\nStart installation now?"
            if ui_yesno "Confirm Installation" "$plan_msg"; then
                run_execution_plan false
                break
            fi
            ;;
        abort | "")
            if ui_yesno "Exit Installer?" "Are you sure you want to exit without applying changes?"; then
                if [ "$TERM" != "dumb" ]; then clear 2>/dev/null || true; fi
                log_info "Exiting Post-Installation Suite. Have a productive day!"
                break
            fi
            ;;
        *)
            menu_activate "$choice"
            ;;
        esac
    done
}
