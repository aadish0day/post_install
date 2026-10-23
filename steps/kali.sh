#!/usr/bin/env bash
# Kali Linux step implementations and plan builder

step_kali_core() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    sudo apt update
    sudo apt install -y nala
    sudo nala update
    sudo nala upgrade -y
    sudo nala install -y git git-lfs stow zsh tmux curl wget vim fzf zoxide lsd trash-cli htop open-vm-tools starship
    mkdir -p ~/cybersec
    if [ ! -d ~/dotfile ]; then
        git clone https://github.com/aadish0day/dotfile.git ~/dotfile
        (cd ~/dotfile && if [ -f link.sh ]; then ./link.sh || true; fi)
    fi
}

step_kali_meta() {
    local meta="$1"
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    sudo nala install -y "kali-linux-${meta}"
}

step_kali_searchsploit() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    if command -v searchsploit &>/dev/null; then
        searchsploit -u || true
    fi
}

step_kali_productivity() {
    local apps_str="$1"
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    PROD_APPS="$apps_str" run_module "debian/apps/productivity.sh"
}

build_plan_kali() {
    local distro_dir="${SCRIPT_DIR}/kali"

    plan_managed_app "docker"
    plan_managed_app "burp"
    plan_managed_app "advcpmv"
    plan_managed_app "productivity"

    plan_add "Kali Linux Core Setup (kali/kali.sh)" step_kali_core

    if [ -n "$CFG_KALI_META" ]; then
        plan_add "Install Kali Metapackage (kali-linux-${CFG_KALI_META})" step_kali_meta "$CFG_KALI_META"
    fi

    if [ "$CFG_KALI_WIFI" = true ] && [ -f "$distro_dir/hardware/wifi.sh" ]; then
        plan_add "Install Realtek WiFi Driver (kali/hardware/wifi.sh)" run_module "kali/hardware/wifi.sh"
    fi

    if [ "$CFG_DOCKER" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
        plan_add "Install Docker CE on Kali (kali/apps/docker.sh)" run_module "kali/apps/docker.sh"
    fi

    if [ "$CFG_SECURITY_BURP" = true ] && [ -f "$distro_dir/apps/burp/install.sh" ]; then
        plan_add "Setup Burp Suite Professional (kali/apps/burp/install.sh)" run_module "kali/apps/burp/install.sh"
    fi

    if [ "$CFG_PRODUCTIVITY" = true ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        plan_add "Install Productivity Applications (${#CFG_PROD_APPS[@]} apps)" \
            step_kali_productivity "${CFG_PROD_APPS[*]}"
    fi

    if [ "$CFG_KALI_SEARCHSPLOIT" = true ]; then
        plan_add "Update SearchSploit Exploit Database" step_kali_searchsploit
    fi

    append_extra_scripts "$distro_dir" "kali"
}
