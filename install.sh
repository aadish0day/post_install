#!/usr/bin/env bash
# ============================================================================
# Post-Installation Automation Suite (Pure Bash Archinstall Orchestrator)
# Re-implements the exact Archinstall-style TUI model and workflow in pure Bash.
# 100% Pure Bash — Zero Python dependencies required.
#
# Every run mirrors the full session (stdout + stderr) to a log in /tmp:
#   /tmp/post-install-YYYYmmdd_HHMMSS.log (symlinked to /tmp/post-install-latest.log)
# ============================================================================

set -euo pipefail
CLEANUP_PIDS=()
cleanup_on_exit() {
    for pid in "${CLEANUP_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    rm -f "${DIALOGRC:-}" 2>/dev/null || true
    ui_restore_cursor
}
trap cleanup_on_exit EXIT
trap 'echo; cleanup_on_exit; exit 130' INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/menu.sh
source "$SCRIPT_DIR/lib/menu.sh"
# shellcheck source=steps/common.sh
source "$SCRIPT_DIR/steps/common.sh"
# shellcheck source=steps/arch.sh
source "$SCRIPT_DIR/steps/arch.sh"
# shellcheck source=steps/debian.sh
source "$SCRIPT_DIR/steps/debian.sh"
# shellcheck source=steps/fedora.sh
source "$SCRIPT_DIR/steps/fedora.sh"
# shellcheck source=steps/kali.sh
source "$SCRIPT_DIR/steps/kali.sh"
# shellcheck source=steps/termux.sh
source "$SCRIPT_DIR/steps/termux.sh"

# ANSI Colors & Badges
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Helper print functions
log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }
log_step() { echo -e "${BOLD}${CYAN}==>${NC} ${BOLD}$1${NC}"; }

# ============================================================================
# LOGGING SUBSYSTEM: mirror the full session (stdout + stderr) into /tmp
# ============================================================================
if [ -n "${POST_INSTALL_LOGGED:-}" ] && [ -n "${POST_INSTALL_LOG_FILE:-}" ]; then
    LOG_FILE="$POST_INSTALL_LOG_FILE"
else
    LOG_FILE="/tmp/post-install-${USER:-$(id -un 2>/dev/null || echo user)}-$(date +%Y%m%d_%H%M%S)-$$.log"
fi

ensure_script() {
    command -v script &>/dev/null && return 0
    local SUDO=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
        SUDO="sudo"
    fi

    echo "Installing 'script' (required for session mirroring)..."
    if [ -d "/data/data/com.termux" ] || [ -n "${TERMUX_VERSION:-}" ] || command -v pkg &>/dev/null; then
        pkg install -y util-linux
    elif command -v pacman &>/dev/null; then
        $SUDO pacman -S --needed --noconfirm util-linux
    elif command -v apt-get &>/dev/null; then
        $SUDO apt-get install -y bsdutils util-linux
    elif command -v dnf &>/dev/null; then
        $SUDO dnf install -y util-linux-script
    elif command -v zypper &>/dev/null; then
        $SUDO zypper --non-interactive install util-linux
    fi
    command -v script &>/dev/null
}

if [ -z "${POST_INSTALL_LOGGED:-}" ]; then
    export POST_INSTALL_LOGGED=1 POST_INSTALL_LOG_FILE="$LOG_FILE"
    ensure_script || true
    if command -v script &>/dev/null; then
        ORIG_TTY=no
        if [ -t 0 ] && [ -t 1 ]; then
            ORIG_TTY=yes
        fi
        export POST_INSTALL_ORIG_TTY="$ORIG_TTY"
        printf '==> Full session log: %s\n' "$LOG_FILE"
        printf -v SELF_Q '%q' "$SCRIPT_DIR/$(basename "$0")"
        printf -v BASH_Q '%q' "$BASH"
        ARGS=""
        for a in "$@"; do
            printf -v aq '%q' "$a"
            ARGS+=" $aq"
        done
        exec script -qefc "$BASH_Q $SELF_Q$ARGS" "$LOG_FILE"
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        exec > >(tee "$LOG_FILE") 2>&1
        trap 'wait; cleanup_on_exit' EXIT
    fi
fi

# Symlink latest log and banner
ln -sf "$LOG_FILE" /tmp/post-install-latest.log 2>/dev/null || true
printf '==> Session start: %s | args: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${*:-none}"
printf '==> Full log: %s\n' "$LOG_FILE"

# ============================================================================
# SYSTEM & HARDWARE DETECTION (Pure Bash)
# ============================================================================
detect_system() {
    # 1. Distro Detection
    if [ -d "/data/data/com.termux" ] || [ -n "${TERMUX_VERSION:-}" ]; then
        DETECTED_DISTRO="termux"
        DISTRO_NAME="Termux (Android)"
    elif [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
        case "${ID:-}" in
            kali) DETECTED_DISTRO="kali" ;;
            arch | manjaro | endeavouros | garuda | artix | cachyos) DETECTED_DISTRO="arch" ;;
            fedora | rhel | centos | rocky | almalinux | nobara) DETECTED_DISTRO="fedora" ;;
            debian | ubuntu | pop | linuxmint | elementary | raspbian) DETECTED_DISTRO="debian" ;;
            *)
                DETECTED_DISTRO="unknown"
                for like in ${ID_LIKE:-}; do
                    case "$like" in
                        arch)
                            DETECTED_DISTRO="arch"
                            break
                            ;;
                        fedora | rhel)
                            DETECTED_DISTRO="fedora"
                            break
                            ;;
                        debian | ubuntu)
                            DETECTED_DISTRO="debian"
                            break
                            ;;
                    esac
                done
                ;;
        esac
    else
        DETECTED_DISTRO="unknown"
        DISTRO_NAME="Unknown Linux"
    fi

    # 2. Host, User, Kernel, Arch
    SYS_HOSTNAME="$(uname -n 2>/dev/null || echo "localhost")"
    SYS_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    SYS_KERNEL="$(uname -r 2>/dev/null || echo "")"
    SYS_ARCH="$(uname -m 2>/dev/null || echo "")"

    # 3. CPU Detection
    CPU_VENDOR="Generic"
    if grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        CPU_VENDOR="AMD"
    elif grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        CPU_VENDOR="Intel"
    elif [ "$SYS_ARCH" = "aarch64" ] || [ "$SYS_ARCH" = "armv7l" ]; then
        CPU_VENDOR="ARM"
    fi
    CPU_MODEL="$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[ \t]*//' || echo "$CPU_VENDOR")"

    # 4. GPU Detection via lspci
    HAS_AMD_GPU=false
    HAS_NVIDIA_GPU=false
    HAS_INTEL_GPU=false
    local lspci_gpus
    lspci_gpus="$(lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' || true)"
    if echo "$lspci_gpus" | grep -Eiq 'amd|ati|radeon'; then HAS_AMD_GPU=true; fi
    if echo "$lspci_gpus" | grep -iq 'nvidia'; then HAS_NVIDIA_GPU=true; fi
    if echo "$lspci_gpus" | grep -iq 'intel'; then HAS_INTEL_GPU=true; fi

    # 5. Chassis & ASUS Hardware Detection
    IS_ASUS=false
    local dmi_info=""
    if [ -f /sys/class/dmi/id/sys_vendor ]; then dmi_info+="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) "; fi
    if [ -f /sys/class/dmi/id/product_name ]; then dmi_info+="$(cat /sys/class/dmi/id/product_name 2>/dev/null) "; fi
    if [ -f /sys/class/dmi/id/product_family ]; then dmi_info+="$(cat /sys/class/dmi/id/product_family 2>/dev/null)"; fi
    if echo "$dmi_info" | grep -Eiq 'asus|rog|tuf|zephyrus|strix|zenbook'; then
        IS_ASUS=true
    fi

    IS_LAPTOP=false
    local chassis_type=""
    if [ -f /sys/class/dmi/id/chassis_type ]; then
        chassis_type="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || true)"
    fi
    if [[ "$chassis_type" =~ ^(8|9|10|11|14|30|31|32)$ ]] || [ -d "/sys/class/power_supply/BAT0" ] || [ -d "/sys/class/power_supply/BAT1" ]; then
        IS_LAPTOP=true
    fi

    # 6. Virtualization Detection
    VIRT_TYPE="none"
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE="$(systemd-detect-virt 2>/dev/null || true)"
    fi
    if [ -z "$VIRT_TYPE" ]; then
        VIRT_TYPE="none"
    fi
}

detect_system

# ============================================================================
# ARCHINSTALL CONFIGURATION STATE (Mirrors core/config.py)
# ============================================================================
TARGET_DISTRO="$DETECTED_DISTRO"
if [ "$TARGET_DISTRO" = "unknown" ]; then
    TARGET_DISTRO="arch"
fi

set_distro_defaults() {
    # 1. Load base configuration defaults
    if [ -f "$SCRIPT_DIR/profiles/_base.conf" ]; then
        # shellcheck source=profiles/_base.conf
        source "$SCRIPT_DIR/profiles/_base.conf"
    fi

    # 2. Load distro-specific configuration defaults
    if [ -f "$SCRIPT_DIR/profiles/${TARGET_DISTRO}.conf" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/profiles/${TARGET_DISTRO}.conf"
    fi

    # 3. Apply hardware-derived values in code
    if [ "$TARGET_DISTRO" = "arch" ] || [ "$TARGET_DISTRO" = "debian" ] || [ "$TARGET_DISTRO" = "fedora" ]; then
        CFG_ASUS="$IS_ASUS"
        CFG_AMD_GPU="$HAS_AMD_GPU"
        if [ "$CPU_VENDOR" = "AMD" ]; then CFG_AMD_GPU=true; fi
        CFG_INTEL_GPU="$HAS_INTEL_GPU"
        if [ "$CPU_VENDOR" = "Intel" ]; then CFG_INTEL_GPU=true; fi
        CFG_NVIDIA_GPU="$HAS_NVIDIA_GPU"
    else
        CFG_ASUS=false
        CFG_AMD_GPU=false
        CFG_INTEL_GPU=false
        CFG_NVIDIA_GPU=false
    fi
}

set_distro_defaults


is_nvim_targeted() {
    # 1. Neovim is already installed on the host
    command -v nvim >/dev/null 2>&1 && return 0

    # 2. Selected in coding tools suite
    if [ "${CFG_CODING:-false}" = true ]; then
        local tool
        for tool in "${CFG_CODING_TOOLS[@]}"; do
            if [ "$tool" = "neovim" ]; then
                return 0
            fi
        done
    fi

    return 1
}

build_plan() {
    plan_init

    case "$TARGET_DISTRO" in
        arch) build_plan_arch ;;
        kali) build_plan_kali ;;
        debian) build_plan_debian ;;
        fedora) build_plan_fedora ;;
        termux) build_plan_termux ;;
    esac

    # Universal steps for all desktop distributions
    if [ "$TARGET_DISTRO" != "termux" ]; then
        if [ "$CFG_NVIM_CLONE" = true ] && is_nvim_targeted; then
            local nvim_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
            if [ ! -d "$nvim_dir" ]; then
                plan_add "Clone Neovim Configuration (Aadishx07/neovim_config)" step_nvim_config
            fi
        fi

        plan_add "Create Standard Directories (~/Pictures/Screenshots)" step_standard_dirs
    fi
}

run_execution_plan() {
    local dry_run="${1:-false}"
    export DRY_RUN_MODE="$dry_run"

    build_plan

    local total_steps=${#PLAN_TITLES[@]}
        if [ "$total_steps" -eq 0 ]; then
            log_warn "No steps planned for execution."
            return 0
        fi

        if [ "$TERM" != "dumb" ]; then clear 2>/dev/null || true; fi
        echo -e "${BOLD}${CYAN}============================================================${NC}"
        echo -e "${BOLD}${CYAN} POST-INSTALLATION SUITE - ARCHINSTALL PURE BASH RUNNER     ${NC}"
        echo -e "${BOLD}${CYAN}============================================================${NC}"
        echo -e " Target Distribution: ${BOLD}${DISTRO_NAME}${NC} (${TARGET_DISTRO})"
        echo -e " Hostname / User:     ${SYS_HOSTNAME} (${SYS_USER})"
        echo -e " CPU / GPU:           ${CPU_MODEL} | AMD:${HAS_AMD_GPU} NV:${HAS_NVIDIA_GPU} Intel:${HAS_INTEL_GPU}"
        echo -e " Mode:                $([ "$dry_run" = true ] && echo -e "${YELLOW}DRY-RUN (Simulation)${NC}" || echo -e "${GREEN}LIVE EXECUTION${NC}")"
        echo -e "${BOLD}${CYAN}============================================================${NC}"
        echo ""
        echo -e "${BOLD}Planned Steps (${total_steps} total):${NC}"
        local i
        for ((i = 0; i < total_steps; i++)); do
            printf "  %2d. %s\n" "$((i + 1))" "${PLAN_TITLES[i]}"
            if [ "$dry_run" = true ]; then
                local step_fn="${PLAN_FNS[i]}"
                local -a step_args=()
                if [ -n "${PLAN_ARGS[i]}" ]; then
                    IFS=$'\x1f' read -r -d '' -a step_args < <(printf "%s\0" "${PLAN_ARGS[i]}")
                fi
                if [ ${#step_args[@]} -gt 0 ]; then
                    printf "      fn: %s %s\n" "$step_fn" "${step_args[*]}"
                else
                    printf "      fn: %s\n" "$step_fn"
                fi
            fi
        done
        echo ""

        if [ "$dry_run" = true ]; then
            log_success "Dry run complete! (0 commands executed)"
            return 0
        fi

        # Keep sudo alive during the plan
        local sudo_pid=""
        if [ "$TARGET_DISTRO" != "termux" ]; then
            if [ "$(id -u)" -ne 0 ]; then
                log_info "Acquiring sudo credentials for installation..."
                if ! sudo -v; then
                    if [ "$TARGET_DISTRO" = "debian" ] && [ -f "$SCRIPT_DIR/debian/system/sudo.sh" ]; then
                        log_warn "Sudo is not configured for user $USER. Launching debian/system/sudo.sh..."
                        if "$SCRIPT_DIR/debian/system/sudo.sh" "$USER"; then
                            log_info "Re-checking sudo credentials..."
                            exec sudo bash "$0" "$@"
                        fi
                    fi
                    log_error "Failed to acquire sudo credentials."
                    return 1
                fi
            fi
            keep_sudo_alive() {
                while true; do
                    sleep 50
                    sudo -n true 2>/dev/null || true
                done
            }
        keep_sudo_alive &
        sudo_pid=$!
        CLEANUP_PIDS+=("$sudo_pid")
        fi

        log_info "Starting execution..."
        local start_total
        start_total=$(date +%s)
        local has_errors=false
        local failed_steps=()

        for ((i = 0; i < total_steps; i++)); do
            local title="${PLAN_TITLES[i]}"
            local fn="${PLAN_FNS[i]}"
            local -a step_args=()
            if [ -n "${PLAN_ARGS[i]}" ]; then
                IFS=$'\x1f' read -r -d '' -a step_args < <(printf "%s\0" "${PLAN_ARGS[i]}")
            fi
            local cwd="${PLAN_CWDS[i]:-$SCRIPT_DIR}"
            local step_num=$((i + 1))

            echo ""
            log_step "[$step_num/$total_steps] $title"
            local step_start
            step_start=$(date +%s)
            local exit_code=0

            (
                cd "$cwd"
                "$fn" "${step_args[@]}"
                ) || exit_code=$?

                local step_duration=$(($(date +%s) - step_start))

                if [ "$exit_code" -eq 0 ]; then
                    echo -e "    ${GREEN}✓ Success (${step_duration}s)${NC}"
                else
                    has_errors=true
                    failed_steps+=("$title")
                    echo -e "    ${RED}✖ FAILED: ${title} (Exit code: ${exit_code}, ${step_duration}s)${NC}"
                    if [ "${STRICT_MODE:-false}" = true ]; then
                        log_error "Aborting immediately on step failure (--strict mode enabled)."
                        break
                    fi
                fi
            done

            if [ -n "$sudo_pid" ]; then
                kill "$sudo_pid" 2>/dev/null || true
            fi

            local total_time=$(($(date +%s) - start_total))

            echo ""
            echo -e "${BOLD}${CYAN}============================================================${NC}"
            if [ "$has_errors" = true ]; then
                echo -e "${RED}${BOLD} Installation finished with WARNINGS/ERRORS in ${total_time}s.${NC}"
                echo -e " Failed steps (${#failed_steps[@]}):"
                    local fstep
                    for fstep in "${failed_steps[@]}"; do
                        echo -e "   - ${RED}${fstep}${NC}"
                    done
                    echo -e " Check the session log for detailed diagnostics: ${LOG_FILE}"
                else
                    echo -e "${GREEN}${BOLD} Installation COMPLETED SUCCESSFULLY in ${total_time}s!${NC}"
                    echo -e " Please restart your session or reboot for all changes to take effect."
            fi
            echo -e "${BOLD}${CYAN}============================================================${NC}"

            if [ -c /dev/tty ] && [ "$FORCE_CLI" = false ]; then
                local done_msg="Post-Installation has finished!\n\nTarget Distribution: ${DISTRO_NAME}\nElapsed Time: ${total_time} seconds\nFull Log: ${LOG_FILE}"
                if [ "$has_errors" = true ]; then
                    done_msg+="\n\nFailed Steps:\n"
                    for fstep in "${failed_steps[@]}"; do
                        done_msg+=" - ${fstep}\n"
                    done
                fi
                done_msg+="\n\nPlease restart your session or reboot for all changes to take effect."
                ui_msg "Installation Complete" "$done_msg"
            fi
}

# ============================================================================
# CLI INTERACTIVE FALLBACK (Non-dialog terminal)
# ============================================================================
run_cli_interactive() {
    [ "$TERM" != "dumb" ] && clear 2>/dev/null || true
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo -e "${BOLD}${CYAN} POST-INSTALLATION SUITE - INTERACTIVE CLI                  ${NC}"
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo -e " Target Distribution: ${BOLD}${DISTRO_NAME}${NC} (${TARGET_DISTRO})"
    echo -e " Hostname / User:     ${SYS_HOSTNAME} (${SYS_USER})"
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo ""
    echo "Options:"
    echo "  1) Install (Run with Current Settings)"
    echo "  2) Toggle Desktop Environment (Current: $CFG_DESKTOP)"
    echo "  3) Toggle Docker ($CFG_DOCKER)"
    echo "  4) Toggle Gaming Stack ($CFG_GAMING)"
    echo "  5) Toggle AI/ML ($CFG_AIML)"
    echo "  6) Switch Distribution ($TARGET_DISTRO)"
    echo "  7) Preview Execution Plan"
    echo "  8) Exit"
    echo ""
    read -rp "Enter choice [1-8] (default: 1): " choice </dev/tty || choice="1"
    choice="${choice:-1}"

    case "$choice" in
        1) run_execution_plan false ;;
        2)
            echo "1) KDE Plasma  2) i3 Window Manager  3) BSPWM  4) Both (i3 + BSPWM)  5) None"
            read -rp "Select desktop [1-5]: " de_c </dev/tty || de_c="1"
            case "$de_c" in
                1) CFG_DESKTOP="kde" ;;
                2) CFG_DESKTOP="i3" ;;
                3) CFG_DESKTOP="bspwm" ;;
                4) CFG_DESKTOP="both" ;;
                *) CFG_DESKTOP="none" ;;
            esac
            run_cli_interactive
            ;;
        3)
            if [ "$CFG_DOCKER" = true ]; then CFG_DOCKER=false; else CFG_DOCKER=true; fi
            run_cli_interactive
            ;;
        4)
            if [ "$CFG_GAMING" = true ]; then CFG_GAMING=false; else CFG_GAMING=true; fi
            run_cli_interactive
            ;;
        5)
            if [ "$CFG_AIML" = true ]; then CFG_AIML=false; else CFG_AIML=true; fi
            run_cli_interactive
            ;;
        6)
            echo "1) Arch  2) Debian  3) Fedora  4) Kali  5) Termux"
            read -rp "Select distro [1-5]: " d_c </dev/tty || d_c="1"
            case "$d_c" in
                1) TARGET_DISTRO="arch" ;;
                2) TARGET_DISTRO="debian" ;;
                3) TARGET_DISTRO="fedora" ;;
                4) TARGET_DISTRO="kali" ;;
                5) TARGET_DISTRO="termux" ;;
            esac
            set_distro_defaults
            run_cli_interactive
            ;;
        7)
            run_execution_plan true
            read -rp "Press Enter to return to menu..." </dev/tty || true
            run_cli_interactive
            ;;
        8)
            log_info "Exiting."
            exit 0
            ;;
        *)
            log_error "Invalid selection."
            exit 1
            ;;
    esac
}

show_help() {
    cat <<EOF
Post-Installation Automation Suite (Pure Bash TUI & Runner)

Usage: $(basename "$0") [OPTIONS]

Options:
  --tui                 Force launch interactive TUI (dialog/whiptail)
  --cli, --headless     Run non-interactively using detected hardware defaults
  --dry-run, -d         Simulate and display execution plan without running commands
  --strict              Abort installation immediately on first failed step
  --distro <distro>     Override distribution (arch, debian, fedora, kali, termux)
  --desktop <de>        Override desktop environment (kde, i3, bspwm, both, none)
  -h, --help            Show this help message

Examples:
  ./install.sh                     # Launch interactive Archinstall TUI
  ./install.sh --dry-run           # Preview execution plan without modifications
  ./install.sh --cli               # Run automated unattended installation
  ./install.sh --distro arch       # Force Arch Linux profile
  ./install.sh --desktop i3        # Target i3 tiling window manager

100% Pure Bash — Zero Python dependencies required.
EOF
}

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================
FORCE_TUI=false
FORCE_CLI=false
DRY_RUN=false
STRICT_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tui)
            FORCE_TUI=true
            shift
            ;;
        --cli | --headless)
            FORCE_CLI=true
            shift
            ;;
        --dry-run | -d)
            DRY_RUN=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --distro)
            TARGET_DISTRO="$2"
            set_distro_defaults
            shift 2
            ;;
        --desktop)
            CFG_DESKTOP="$2"
            shift 2
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            log_warn "Unknown argument: $1"
            shift
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    run_execution_plan true
    exit 0
fi

if [ "$FORCE_CLI" = true ]; then
    run_execution_plan false
    exit 0
fi

if [ "$FORCE_TUI" = true ]; then
    ui_ensure_dialog
    ui_detect
    if [ "$UI_TOOL" = "none" ]; then
        log_error "Could not initialize TUI: neither 'dialog' nor 'whiptail' is available."
        exit 1
    fi
    run_tui
    exit 0
fi

# TUI is default when interactive
if [ -t 0 ] && [ -t 1 ]; then
    ui_ensure_dialog
    run_tui
else
    run_execution_plan false
fi
