#!/usr/bin/env bash
# Kali Linux step implementations and plan builder

# All tool checkouts (web pentest tools, wordlists) live under one directory.
export TOOL_DIR="${TOOL_DIR:-$HOME/cybersec}"

step_kali_core() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi

    local apt_opts=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    local pm="apt-get"

    sudo apt-get update || return 1
    if sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nala; then
        pm="nala"
        sudo nala update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive nala upgrade --download-only -y || warn "nala pre-download failed; apt will download instead."
    else
        warn "nala unavailable; using apt-get."
    fi
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" full-upgrade || return 1

    local pkgs=(git git-lfs stow zsh tmux curl wget vim fzf zoxide lsd trash-cli htop starship nodejs npm neovim)
    # open-vm-tools only makes sense on VMware guests
    if [ "$(systemd-detect-virt 2>/dev/null || true)" = "vmware" ]; then
        pkgs+=(open-vm-tools)
    fi
    if [ "$pm" = "nala" ]; then
        sudo env DEBIAN_FRONTEND=noninteractive nala install -y "${pkgs[@]}" || return 1
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" install "${pkgs[@]}" || return 1
    fi

    mkdir -p "$TOOL_DIR"
    if [ ! -d ~/dotfile ]; then
        git clone https://github.com/aadish0day/dotfile.git ~/dotfile || return 1
        (cd ~/dotfile && if [ -f link.sh ]; then ./link.sh || true; fi)
    fi
}

step_kali_meta() {
    local meta="${1:-}"
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    [ -n "$meta" ] && [ "$meta" != "none" ] || return 0
    if command -v nala &>/dev/null; then
        sudo env DEBIAN_FRONTEND=noninteractive nala install -y "kali-linux-${meta}"
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "kali-linux-${meta}"
    fi
}

step_kali_searchsploit() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    if ! command -v searchsploit &>/dev/null; then
        warn "searchsploit not installed (install exploitdb or a kali-linux-* metapackage first); skipping."
        return 0
    fi
    searchsploit -u
}

build_plan_kali() {
    local distro_dir="${SCRIPT_DIR}/kali"

    plan_managed_app "docker"
    plan_managed_app "lazydocker"
    plan_managed_app "burp"
    plan_managed_app "advcpmv"

    plan_add "Kali Linux Core Setup (apt/nala upgrade, base tools, dotfiles)" step_kali_core

    if [ -n "${CFG_KALI_META:-}" ] && [ "${CFG_KALI_META:-}" != "none" ]; then
        plan_add "Install Kali Metapackage (kali-linux-${CFG_KALI_META})" step_kali_meta "${CFG_KALI_META}"
    fi

    if [ "${CFG_KALI_USER_SETUP:-false}" = true ] && [ -f "$distro_dir/system/user.sh" ]; then
        plan_add "Create Pentest User (kali/system/user.sh, interactive)" run_module "kali/system/user.sh"
    fi

    if [ "${CFG_KALI_WIFI:-false}" = true ] && [ -f "$distro_dir/hardware/wifi.sh" ]; then
        plan_add "Install Realtek RTL88xxAU WiFi Driver (kali/hardware/wifi.sh)" run_module "kali/hardware/wifi.sh"
    fi

    if [ "${CFG_DOCKER:-false}" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
        plan_add "Install Docker CE on Kali (kali/apps/docker.sh)" run_module "kali/apps/docker.sh"

        if [ -f "$distro_dir/apps/lazydocker.sh" ]; then
            plan_add "Install lazydocker TUI (kali/apps/lazydocker.sh)" run_module "kali/apps/lazydocker.sh"
        fi
    fi

    local -a burp_args=(--skip-launch)
    if [ "${CFG_SECURITY_BURP:-false}" = true ] && [ -f "$distro_dir/apps/burp/install.sh" ]; then
        plan_add "Setup Burp Suite Professional (kali/apps/burp/install.sh)" run_module "kali/apps/burp/install.sh" "${burp_args[@]}"
    fi

    if [ "${CFG_KALI_WEBTOOLS:-false}" = true ] && [ -d "$distro_dir/apps/web" ]; then
        local web_script web_name
        for web_script in "$distro_dir"/apps/web/*.sh; do
            [ -f "$web_script" ] || continue
            web_name="$(basename "$web_script" .sh)"
            case "$web_name" in _*) continue ;; esac # skip helpers such as _common.sh
            plan_add "Install Web Pentest Tool: ${web_name} (kali/apps/web/${web_name}.sh)" run_module "kali/apps/web/${web_name}.sh"
        done
    fi

    if [ "${CFG_ADVCPMV:-false}" = true ] && [ -f "$distro_dir/apps/advcpmv.sh" ]; then
        plan_add "Install Advanced Copy with Progress Bar (kali/apps/advcpmv.sh)" run_module "kali/apps/advcpmv.sh"
    fi

    if [ "${CFG_KALI_SEARCHSPLOIT:-false}" = true ]; then
        plan_add "Update SearchSploit Exploit Database" step_kali_searchsploit
    fi

    append_extra_scripts "$distro_dir" "kali"
}
