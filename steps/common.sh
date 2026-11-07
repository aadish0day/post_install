#!/usr/bin/env bash
# Common step definitions and execution engine primitives

PLAN_TITLES=()
PLAN_FNS=()
PLAN_ARGS=()
PLAN_CWDS=()
PLAN_MANAGED_APPS=()

plan_init() {
    PLAN_TITLES=()
    PLAN_FNS=()
    PLAN_ARGS=()
    PLAN_CWDS=()
    PLAN_MANAGED_APPS=()
}

plan_managed_app() {
    local app="$1"
    PLAN_MANAGED_APPS+=("$app")
}

plan_add() {
    local title="$1"
    local fn="$2"
    shift 2
    local args=("$@")

    PLAN_TITLES+=("$title")
    PLAN_FNS+=("$fn")
    PLAN_CWDS+=("${PLAN_STEP_CWD:-$PWD}")

    local serialized=""
    if [ ${#args[@]} -gt 0 ]; then
        printf -v serialized "%s\x1f" "${args[@]}"
    fi
    PLAN_ARGS+=("$serialized")
}

thorium_pkg() {
    if grep -qw avx2 /proc/cpuinfo 2>/dev/null; then
        echo "thorium-browser-avx2-bin"
    elif grep -qw avx /proc/cpuinfo 2>/dev/null; then
        echo "thorium-browser-avx-bin"
    elif grep -qw sse4_1 /proc/cpuinfo 2>/dev/null; then
        echo "thorium-browser-sse4-bin"
    else
        echo "thorium-browser-bin"
    fi
}

aur_cmd() {
    if [ "${CFG_AUR:-}" = "yay" ] && command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    elif command -v yay &>/dev/null; then
        echo "yay"
    else
        echo ""
    fi
}

append_extra_scripts() {
    local d_dir="$1"
    local d_name="$2"
    local apps_dir="$d_dir/apps"
    [ -d "$apps_dir" ] || return 0

    local extra stem is_managed m
    for extra in "$apps_dir"/*.sh; do
        [ -f "$extra" ] || continue
        stem="$(basename "$extra" .sh)"
        is_managed=false
        for m in "${PLAN_MANAGED_APPS[@]}"; do
            if [ "$m" = "$stem" ]; then
                is_managed=true
                break
            fi
        done
        if [ "$is_managed" = false ]; then
            local rel_script="${d_name}/apps/${stem}.sh"
            plan_add "Run Extra App Script: ${rel_script}" run_module "$rel_script"
        fi
    done
}

step_nvim_config() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    local nvim_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    local repo_url="${CFG_NVIM_REPO:-https://github.com/Aadishx07/neovim_config.git}"
    if [ ! -d "$nvim_dir" ]; then
        mkdir -p "$(dirname "$nvim_dir")"
        git clone "$repo_url" "$nvim_dir"
    fi
}

step_standard_dirs() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi
    mkdir -p "$HOME/Pictures/Screenshots"
}

step_burp_trust_ca() {
    if [ "${DRY_RUN_MODE:-false}" = true ]; then return 0; fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$script_dir/lib/burp-common.sh" ]; then
        # shellcheck source=/dev/null
        source "$script_dir/lib/burp-common.sh"
    fi

    local burp_bin=""
    if command -v find_burp_bin &>/dev/null; then
        burp_bin="$(find_burp_bin 2>/dev/null || true)"
    fi
    if [ -z "$burp_bin" ] && command -v burpsuitepro &>/dev/null; then
        burp_bin="$(command -v burpsuitepro)"
    fi

    if [ -z "$burp_bin" ]; then
        echo "Burp Suite launcher not found. Skipping CA trust step."
        return 0
    fi

    # Verify if Burp Suite proxy is actively running and responding with a PortSwigger CA certificate
    local chk_tmp
    chk_tmp="$(mktemp "${TMPDIR:-/tmp}/burp-common-chk-XXXXXX.tmp" 2>/dev/null || mktemp /tmp/burp-common-chk-XXXXXX.tmp)"
    local burp_active=false
    if curl -sSL -f -m 2 http://127.0.0.1:8080/cert -o "$chk_tmp" 2>/dev/null && [ -s "$chk_tmp" ]; then
        local cert_subj
        cert_subj="$(openssl x509 -inform DER -in "$chk_tmp" -noout -subject -issuer 2>/dev/null ||
            openssl x509 -inform PEM -in "$chk_tmp" -noout -subject -issuer 2>/dev/null || true)"
        if [ -n "$cert_subj" ] && echo "$cert_subj" | grep -qi "PortSwigger"; then
            burp_active=true
        fi
    fi
    rm -f "$chk_tmp"

    if [ "$burp_active" = false ]; then
        echo ""
        echo "Burp Suite proxy is not currently active (installed with --skip-launch) or not serving a valid PortSwigger certificate."
        echo "Skipping unattended CA trust. To trust Burp CA certificate across browsers once Burp is running, run: 'burpsuitepro --trust-ca'."
        return 0
    fi

    echo ""
    echo "=================================================="
    echo "  Burp Suite CA Certificate Auto-Trust Setup     "
    echo "=================================================="
    echo "All applications & browsers have been installed."
    echo "Configuring Burp CA certificate across detected browsers..."

    if ! "$burp_bin" --trust-ca --all; then
        echo ""
        echo "[!] Note: Burp CA certificate auto-trust could not complete automatically."
        echo "    If Burp Suite is starting for the first time, complete license activation."
        echo "    Then run 'burpsuitepro --trust-ca' anytime in a terminal."
        return 0
    fi
}
