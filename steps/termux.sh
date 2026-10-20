#!/usr/bin/env bash
# Termux step implementations and plan builder

build_plan_termux() {
    local distro_dir="${SCRIPT_DIR}/termux"

    if [ -f "$distro_dir/termux.sh" ]; then
        plan_add "Setup Termux Environment (termux/termux.sh)" run_module "termux/termux.sh"
    fi

    if [ "$CFG_FONTS" = true ] && [ -f "$distro_dir/system/font.sh" ]; then
        plan_add "Install JetBrains Mono Font (termux/system/font.sh)" run_module "termux/system/font.sh"
    fi

    append_extra_scripts "$distro_dir" "termux"
}
