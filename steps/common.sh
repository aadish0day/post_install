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

run_module() {
    local script="$1"
    shift
    local args=("$@")

    if [[ "$script" != /* ]]; then
        script="$SCRIPT_DIR/$script"
    fi

    if [ ! -f "$script" ]; then
        echo "Error: script not found: $script" >&2
        return 1
    fi

    local parent_dir
    parent_dir="$(cd "$(dirname "$script")/.." && pwd)"

    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        return 0
    fi

    (
        cd "$parent_dir" || exit 1
        bash "$script" "${args[@]}"
    )
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
