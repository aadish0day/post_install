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
    printf '\033[?25h\033[0 q' >/dev/tty 2>/dev/null || tput cnorm 2>/dev/null || true
}
trap cleanup_on_exit EXIT
trap 'echo; cleanup_on_exit; exit 130' INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    LOG_FILE="/tmp/post-install-$(date +%Y%m%d_%H%M%S).log"
fi

ensure_script() {
    command -v script &>/dev/null && return 0
    local SUDO=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
        SUDO="sudo"
    fi

    echo "Installing 'script' (required for session mirroring)..."
    if command -v pacman &>/dev/null; then
        $SUDO pacman -S --needed --noconfirm util-linux
    elif command -v apt-get &>/dev/null; then
        $SUDO apt-get install -y bsdutils util-linux
    elif command -v dnf &>/dev/null; then
        $SUDO dnf install -y util-linux-script
    elif command -v zypper &>/dev/null; then
        $SUDO zypper --non-interactive install util-linux
    elif [ -d "/data/data/com.termux" ] || [ -n "${TERMUX_VERSION:-}" ]; then
        pkg install -y util-linux
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
        trap 'wait' EXIT
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
    case "$TARGET_DISTRO" in
    arch)
        DISTRO_NAME="Arch Linux"
        CFG_DESKTOP="none"
        CFG_ASUS="$IS_ASUS"
        CFG_ASUS_LIMIT=85
        CFG_AMD_GPU="$HAS_AMD_GPU"
        if [ "$CPU_VENDOR" = "AMD" ]; then CFG_AMD_GPU=true; fi
        CFG_AMD_PRO=false
        CFG_INTEL_GPU="$HAS_INTEL_GPU"
        if [ "$CPU_VENDOR" = "Intel" ]; then CFG_INTEL_GPU=true; fi
        CFG_NVIDIA_GPU="$HAS_NVIDIA_GPU"
        CFG_TOUCHPAD=false
        CFG_KVM=true
        CFG_VMWARE=false
        CFG_DOCKER=true
        CFG_CODING=true
        CFG_CODING_TOOLS=("vscode" "cursor" "claude_code" "android_studio" "flutter" "antigravity")
        CFG_SECURITY_BURP=false
        CFG_GAMING=false
        CFG_AIML=false
        CFG_AUR="paru"
        CFG_MIRRORS=true
        CFG_PRODUCTIVITY=true
        CFG_PROD_APPS=("thorium" "zen" "vesktop" "localsend" "anydesk" "obsidian" "markitdown" "gallery_dl" "ani_cli" "advcpmv")
        CFG_FONTS=true
        CFG_NVIM_CLONE=true
        ;;
    kali)
        DISTRO_NAME="Kali Linux"
        CFG_DESKTOP="none"
        CFG_ASUS=false
        CFG_ASUS_LIMIT=85
        CFG_AMD_GPU=false
        CFG_AMD_PRO=false
        CFG_INTEL_GPU=false
        CFG_NVIDIA_GPU=false
        CFG_TOUCHPAD=false
        CFG_KVM=false
        CFG_VMWARE=false
        CFG_DOCKER=true
        CFG_CODING=false
        CFG_CODING_TOOLS=()
        CFG_SECURITY_BURP=true
        CFG_KALI_META="large"
        CFG_KALI_WIFI=true
        CFG_KALI_SEARCHSPLOIT=true
        CFG_GAMING=false
        CFG_AIML=false
        CFG_AUR="none"
        CFG_MIRRORS=false
        CFG_PRODUCTIVITY=false
        CFG_PROD_APPS=()
        CFG_FONTS=true
        CFG_NVIM_CLONE=true
        ;;
    debian | fedora)
        if [ "$TARGET_DISTRO" = "debian" ]; then
            DISTRO_NAME="Debian / Ubuntu"
        else
            DISTRO_NAME="Fedora"
        fi
        CFG_DESKTOP="none"
        CFG_ASUS="$IS_ASUS"
        CFG_ASUS_LIMIT=85
        CFG_AMD_GPU="$HAS_AMD_GPU"
        if [ "$CPU_VENDOR" = "AMD" ]; then CFG_AMD_GPU=true; fi
        CFG_AMD_PRO=false
        CFG_INTEL_GPU="$HAS_INTEL_GPU"
        if [ "$CPU_VENDOR" = "Intel" ]; then CFG_INTEL_GPU=true; fi
        CFG_NVIDIA_GPU="$HAS_NVIDIA_GPU"
        CFG_TOUCHPAD=false
        CFG_KVM=true
        CFG_VMWARE=false
        CFG_DOCKER=true
        CFG_CODING=true
        CFG_CODING_TOOLS=("neovim" "vscode" "cursor" "claude_code" "android_studio" "flutter" "antigravity")
        CFG_SECURITY_BURP=false
        CFG_GAMING=false
        CFG_AIML=false
        CFG_AUR="none"
        CFG_MIRRORS=false
        CFG_PRODUCTIVITY=true
        CFG_PROD_APPS=("thorium" "zen" "vesktop" "localsend" "anydesk" "obsidian" "markitdown" "gallery_dl" "ani_cli")
        CFG_FONTS=true
        CFG_NVIM_CLONE=true
        ;;
    termux)
        DISTRO_NAME="Termux"
        CFG_DESKTOP="none"
        CFG_ASUS=false
        CFG_ASUS_LIMIT=85
        CFG_AMD_GPU=false
        CFG_AMD_PRO=false
        CFG_INTEL_GPU=false
        CFG_NVIDIA_GPU=false
        CFG_TOUCHPAD=false
        CFG_KVM=false
        CFG_VMWARE=false
        CFG_DOCKER=false
        CFG_CODING=true
        CFG_CODING_TOOLS=("neovim")
        CFG_SECURITY_BURP=false
        CFG_GAMING=false
        CFG_AIML=false
        CFG_AUR="none"
        CFG_MIRRORS=false
        CFG_PRODUCTIVITY=false
        CFG_PROD_APPS=()
        CFG_FONTS=true
        CFG_NVIM_CLONE=true
        ;;
    esac
}

set_distro_defaults

# ============================================================================
# TUI UTILITIES & VIM KEYBINDINGS (dialog / whiptail)
# ============================================================================
setup_vim_keybindings() {
    local rc_file="${TMPDIR:-/tmp}/.dialogrc_post_install_$$"
    cat <<'EOF' >"$rc_file"
use_shadow = ON
use_colors = ON

# Input box high-contrast styling: bold white text on blue background prevents invisible cursor on dark terminals
inputbox_color = (WHITE,BLUE,ON)
inputbox_border_color = (CYAN,BLUE,ON)
inputbox_border2_color = (CYAN,BLUE,ON)

# Checklist navigation: j (\152), k (\153), g (\147), G (\107), h (\150), l (\154)
bindkey checklist \152 ITEM_NEXT
bindkey checklist \153 ITEM_PREV
bindkey checklist \147 PAGE_FIRST
bindkey checklist \107 PAGE_LAST
bindkey checklist \150 FIELD_PREV
bindkey checklist \154 FIELD_NEXT

# Menu navigation
bindkey menu \152 ITEM_NEXT
bindkey menu \153 ITEM_PREV
bindkey menu \147 PAGE_FIRST
bindkey menu \107 PAGE_LAST
bindkey menu \150 FIELD_PREV
bindkey menu \154 FIELD_NEXT

# Menubox navigation
bindkey menubox \152 ITEM_NEXT
bindkey menubox \153 ITEM_PREV
bindkey menubox \147 PAGE_FIRST
bindkey menubox \107 PAGE_LAST
bindkey menubox \150 FIELD_PREV
bindkey menubox \154 FIELD_NEXT

# Msgbox navigation
bindkey msgbox \150 FIELD_PREV
bindkey msgbox \154 FIELD_NEXT
bindkey msgbox \152 FIELD_NEXT
bindkey msgbox \153 FIELD_PREV

# YesNo navigation
bindkey yesno \150 FIELD_PREV
bindkey yesno \154 FIELD_NEXT
bindkey yesno \152 FIELD_NEXT
bindkey yesno \153 FIELD_PREV
EOF
    export DIALOGRC="$rc_file"
}

get_tui_tool() {
    if command -v dialog >/dev/null 2>&1; then
        echo "dialog"
    elif command -v whiptail >/dev/null 2>&1; then
        echo "whiptail"
    else
        echo "none"
    fi
}

# Auto-discover extra scripts in <distro>/apps/
append_extra_scripts() {
    local d_dir="$1"
    local d_name="$2"
    local apps_dir="$d_dir/apps"
    [ -d "$apps_dir" ] || return 0

    local managed=()
    case "$d_name" in
    arch) managed=("docker" "gaming" "paru" "yay" "flutter") ;;
    kali) managed=("docker") ;;
    debian) managed=("docker" "neovim" "coding" "gaming" "aiml" "productivity") ;;
    fedora) managed=("docker" "coding" "gaming" "aiml" "productivity") ;;
    termux) managed=() ;;
    esac

    for extra in "$apps_dir"/*.sh; do
        [ -f "$extra" ] || continue
        local stem
        stem="$(basename "$extra" .sh)"
        local is_managed=false
        for m in "${managed[@]}"; do
            if [ "$m" = "$stem" ]; then
                is_managed=true
                break
            fi
        done
        if [ "$is_managed" = false ]; then
            PLAN_TITLES+=("Run Extra App Script: ${d_name}/apps/${stem}.sh")
            PLAN_COMMANDS+=("bash apps/${stem}.sh")
            PLAN_CWDS+=("$d_dir")
        fi
    done
}

# ============================================================================
# EXECUTION ENGINE: Build and execute installation plan
# ============================================================================
build_plan() {
    PLAN_TITLES=()
    PLAN_COMMANDS=()
    PLAN_CWDS=()

    local distro_dir="${SCRIPT_DIR}/${TARGET_DISTRO}"

    # ---------------- ARCH LINUX ----------------
    if [ "$TARGET_DISTRO" = "arch" ]; then
        if [ "$CFG_MIRRORS" = true ]; then
            PLAN_TITLES+=("Optimize Mirrorlist (Reflector India)")
            PLAN_COMMANDS+=("sudo pacman -Sy --noconfirm && sudo pacman -S --needed reflector --noconfirm --overwrite '*' && timeout 30s sudo reflector --latest 10 --fastest 5 --protocol https --connection-timeout 5 --download-timeout 5 --threads 8 --country India --sort rate --save /etc/pacman.d/mirrorlist || echo 'Reflector timed out or failed; keeping existing mirrorlist.' && sudo pacman -Syu --noconfirm --overwrite '*'")
            PLAN_CWDS+=("$distro_dir")
        fi

        PLAN_TITLES+=("Install Arch Base Packages & Utilities")
        PLAN_COMMANDS+=("sudo pacman -S --needed --noconfirm --overwrite '*' android-tools aria2 atool bat chromaprint doxygen duf fastfetch fd fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly highlight htop img2pdf imagemagick inxi jq jpegoptim less libavtp libdca libgme liblrdf libltc libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv ncdu neovim nodejs npm obs-studio 7zip pacman-contrib pacutils parallel pipewire pipewire-alsa pipewire-audio pipewire-jack lib32-pipewire-jack pipewire-pulse pipewire-zeroconf pipewire-libcamera pkgfile plocate pv ripgrep sd spandsp starship soundtouch svt-hevc tar tree tree-sitter-cli trash-cli tmux unzip wireplumber xz yazi yt-dlp zip zoxide zsh zstd dosfstools usbutils lazydocker opencode github-cli && if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then git lfs install --skip-repo; fi")
        PLAN_CWDS+=("$distro_dir")

        if [ "$CFG_AUR" = "paru" ] || [ "$CFG_AUR" = "both" ]; then
            if [ -f "$distro_dir/apps/paru.sh" ]; then
                PLAN_TITLES+=("Install Paru AUR Helper (arch/apps/paru.sh)")
                PLAN_COMMANDS+=("bash apps/paru.sh")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        if [ "$CFG_AUR" = "yay" ] || [ "$CFG_AUR" = "both" ]; then
            if [ -f "$distro_dir/apps/yay.sh" ]; then
                PLAN_TITLES+=("Install Yay AUR Helper (arch/apps/yay.sh)")
                PLAN_COMMANDS+=("bash apps/yay.sh")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        if [ "$CFG_AMD_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/amd.sh" ]; then
            local cmd="bash hardware/gpu/amd.sh"
            if [ "$CFG_AMD_PRO" = true ]; then cmd+=" --pro"; fi
            PLAN_TITLES+=("AMD CPU/GPU Drivers & P-State Optimization (arch/hardware/gpu/amd.sh)")
            PLAN_COMMANDS+=("$cmd")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_INTEL_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/intel.sh" ]; then
            PLAN_TITLES+=("Intel CPU/GPU Drivers (arch/hardware/gpu/intel.sh)")
            PLAN_COMMANDS+=("bash hardware/gpu/intel.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_NVIDIA_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/nvidia.sh" ]; then
            PLAN_TITLES+=("NVIDIA GPU Drivers (arch/hardware/gpu/nvidia.sh)")
            PLAN_COMMANDS+=("bash hardware/gpu/nvidia.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_ASUS" = true ] && [ -f "$distro_dir/hardware/asus.sh" ]; then
            PLAN_TITLES+=("Configure ASUS ROG & Power Tooling (arch/hardware/asus.sh)")
            PLAN_COMMANDS+=("bash hardware/asus.sh ${CFG_ASUS_LIMIT}")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_TOUCHPAD" = true ] && [ -f "$distro_dir/hardware/touchpad.sh" ]; then
            PLAN_TITLES+=("Configure Precision Touchpad (arch/hardware/touchpad.sh)")
            PLAN_COMMANDS+=("bash hardware/touchpad.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_DESKTOP" = "kde" ] && [ -f "$distro_dir/desktop/kde.sh" ]; then
            PLAN_TITLES+=("Install KDE Plasma Desktop (arch/desktop/kde.sh)")
            PLAN_COMMANDS+=("bash desktop/kde.sh")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "i3" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
            PLAN_TITLES+=("Install i3 Tiling Window Manager (arch/desktop/tiling.sh i3)")
            PLAN_COMMANDS+=("bash desktop/tiling.sh i3")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "bspwm" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
            PLAN_TITLES+=("Install BSPWM Tiling Window Manager (arch/desktop/tiling.sh bspwm)")
            PLAN_COMMANDS+=("bash desktop/tiling.sh bspwm")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "tiling" ] || [ "$CFG_DESKTOP" = "both" ]; then
            if [ -f "$distro_dir/desktop/tiling.sh" ]; then
                PLAN_TITLES+=("Install X11 Tiling Window Managers (arch/desktop/tiling.sh both)")
                PLAN_COMMANDS+=("bash desktop/tiling.sh both")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        if [ "$CFG_KVM" = true ] && [ -f "$distro_dir/virt/kvm-qemu.sh" ]; then
            PLAN_TITLES+=("Setup KVM, QEMU & virt-manager (arch/virt/kvm-qemu.sh)")
            PLAN_COMMANDS+=("bash virt/kvm-qemu.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_VMWARE" = true ] && [ -f "$distro_dir/virt/vmware-workstation.sh" ]; then
            PLAN_TITLES+=("Install VMware Workstation (arch/virt/vmware-workstation.sh)")
            PLAN_COMMANDS+=("bash virt/vmware-workstation.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_DOCKER" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
            PLAN_TITLES+=("Install Docker Engine & Buildx (arch/apps/docker.sh)")
            PLAN_COMMANDS+=("bash apps/docker.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_CODING" = true ]; then
            local pkgs=()
            local run_flutter=false
            for t in "${CFG_CODING_TOOLS[@]}"; do
                case "$t" in
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
            if [ ${#pkgs[@]} -gt 0 ] || [ "$run_flutter" = true ]; then
                local coding_cmd="aur_cmd=''; if command -v paru &>/dev/null; then aur_cmd='paru'; elif command -v yay &>/dev/null; then aur_cmd='yay'; fi"
                if [ ${#pkgs[@]} -gt 0 ]; then
                    coding_cmd+="; if [ -n \"\$aur_cmd\" ]; then \$aur_cmd -S --needed --noconfirm ${pkgs[*]} || true; fi"
                fi
                if [ "$run_flutter" = true ]; then
                    coding_cmd+="; if [ -f apps/flutter.sh ]; then bash apps/flutter.sh; fi"
                fi
                PLAN_TITLES+=("Install Developer & Coding Suite (AUR)")
                PLAN_COMMANDS+=("$coding_cmd")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        if [ "$CFG_SECURITY_BURP" = true ] && [ -f "$distro_dir/apps/burp/install.sh" ]; then
            PLAN_TITLES+=("Setup Burp Suite Professional (arch/apps/burp/install.sh)")
            PLAN_COMMANDS+=("bash apps/burp/install.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_GAMING" = true ] && [ -f "$distro_dir/apps/gaming.sh" ]; then
            PLAN_TITLES+=("Setup Gaming Stack (arch/apps/gaming.sh)")
            PLAN_COMMANDS+=("bash apps/gaming.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_AIML" = true ]; then
            PLAN_TITLES+=("Install ROCm & AI/ML Acceleration Suite")
            PLAN_COMMANDS+=("sudo pacman -S --needed --noconfirm --overwrite '*' rocm-llvm rocm-opencl-runtime rocm-opencl-sdk rocm-hip-sdk rocm-ml-libraries rocm-openmp hipify-clang rocminfo opencl-headers libclc ocl-icd python-pytorch-rocm python-onnxruntime-rocm")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_PRODUCTIVITY" = true ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
            local prod_pkgs=()
            local need_thorium=false
            for p in "${CFG_PROD_APPS[@]}"; do
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
                esac
            done

            if [ "$need_thorium" = true ] || [ ${#prod_pkgs[@]} -gt 0 ]; then
                local prod_cmd="aur_cmd=''; if command -v paru &>/dev/null; then aur_cmd='paru'; elif command -v yay &>/dev/null; then aur_cmd='yay'; fi; if [ -n \"\$aur_cmd\" ]; then "
                if [ "$need_thorium" = true ]; then
                    prod_cmd+="thorium_pkg='thorium-browser-bin'; if grep -qw avx2 /proc/cpuinfo 2>/dev/null; then thorium_pkg='thorium-browser-avx2-bin'; elif grep -qw avx /proc/cpuinfo 2>/dev/null; then thorium_pkg='thorium-browser-avx-bin'; elif grep -qw sse4_1 /proc/cpuinfo 2>/dev/null; then thorium_pkg='thorium-browser-sse4-bin'; fi; "
                    prod_pkgs+=("\$thorium_pkg")
                fi
                prod_cmd+="\$aur_cmd -S --needed --noconfirm ${prod_pkgs[*]} || true; fi"

                PLAN_TITLES+=("Install Essential AUR Productivity Tools (${#CFG_PROD_APPS[@]} apps)")
                PLAN_COMMANDS+=("$prod_cmd")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        append_extra_scripts "$distro_dir" "arch"

        PLAN_TITLES+=("Configure Services & Default Shell")
        PLAN_COMMANDS+=("for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do if systemctl --user list-unit-files 2>/dev/null | grep -q \"\$s\"; then systemctl --user start \"\$s\" 2>/dev/null || true; fi; done; if [ \"\$SHELL\" != \"\$(command -v zsh 2>/dev/null || echo '')\" ] && command -v zsh &>/dev/null; then chsh -s \"\$(command -v zsh)\" \"\$USER\" 2>/dev/null || true; fi")
        PLAN_CWDS+=("$distro_dir")

    # ---------------- KALI LINUX ----------------
    elif [ "$TARGET_DISTRO" = "kali" ]; then
        PLAN_TITLES+=("Kali Linux Core Setup (kali/kali.sh)")
        PLAN_COMMANDS+=("sudo apt update && sudo apt install -y nala && sudo nala update && sudo nala upgrade -y && sudo nala install -y git git-lfs stow zsh tmux curl wget vim neovim fzf zoxide lsd trash-cli htop open-vm-tools starship && mkdir -p ~/cybersec && if [ ! -d ~/dotfile ]; then git clone https://github.com/aadish0day/dotfile.git ~/dotfile && (cd ~/dotfile && [ -f link.sh ] && ./link.sh || true); fi")
        PLAN_CWDS+=("$distro_dir")

        if [ -n "$CFG_KALI_META" ]; then
            PLAN_TITLES+=("Install Kali Metapackage (kali-linux-${CFG_KALI_META})")
            PLAN_COMMANDS+=("sudo nala install -y kali-linux-${CFG_KALI_META}")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_KALI_WIFI" = true ] && [ -f "$distro_dir/hardware/wifi.sh" ]; then
            PLAN_TITLES+=("Install Realtek WiFi Driver (kali/hardware/wifi.sh)")
            PLAN_COMMANDS+=("bash hardware/wifi.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_DOCKER" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
            PLAN_TITLES+=("Install Docker CE on Kali (kali/apps/docker.sh)")
            PLAN_COMMANDS+=("bash apps/docker.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_SECURITY_BURP" = true ] && [ -f "$distro_dir/apps/burp/install.sh" ]; then
            PLAN_TITLES+=("Setup Burp Suite Professional (kali/apps/burp/install.sh)")
            PLAN_COMMANDS+=("bash apps/burp/install.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_KALI_SEARCHSPLOIT" = true ]; then
            PLAN_TITLES+=("Update SearchSploit Exploit Database")
            PLAN_COMMANDS+=("if command -v searchsploit &>/dev/null; then searchsploit -u || true; fi")
            PLAN_CWDS+=("$distro_dir")
        fi

        append_extra_scripts "$distro_dir" "kali"

    # ---------------- DEBIAN / UBUNTU & FEDORA ----------------
    elif [ "$TARGET_DISTRO" = "debian" ] || [ "$TARGET_DISTRO" = "fedora" ]; then
        if [ "$TARGET_DISTRO" = "fedora" ] && [ -f "$distro_dir/system/dnf.sh" ]; then
            PLAN_TITLES+=("Configure DNF & Performance Tweaks (fedora/system/dnf.sh)")
            PLAN_COMMANDS+=("bash system/dnf.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ -f "$distro_dir/system/repos.sh" ]; then
            PLAN_TITLES+=("Configure System Repositories (${TARGET_DISTRO}/system/repos.sh)")
            PLAN_COMMANDS+=("bash system/repos.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$TARGET_DISTRO" = "debian" ] && [ -f "$distro_dir/system/pacstall.sh" ]; then
            PLAN_TITLES+=("Install Pacstall AUR Helper for Debian (debian/system/pacstall.sh)")
            PLAN_COMMANDS+=("bash system/pacstall.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ -f "$distro_dir/system/flatpak.sh" ]; then
            PLAN_TITLES+=("Configure Flatpak & Flathub (${TARGET_DISTRO}/system/flatpak.sh)")
            PLAN_COMMANDS+=("bash system/flatpak.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ -f "$distro_dir/system/base.sh" ]; then
            PLAN_TITLES+=("Install Base Packages (${TARGET_DISTRO}/system/base.sh)")
            PLAN_COMMANDS+=("bash system/base.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_AMD_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/amd.sh" ]; then
            PLAN_TITLES+=("Configure AMD Graphics Drivers (${TARGET_DISTRO}/hardware/gpu/amd.sh)")
            PLAN_COMMANDS+=("bash hardware/gpu/amd.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_INTEL_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/intel.sh" ]; then
            PLAN_TITLES+=("Configure Intel Graphics Drivers (${TARGET_DISTRO}/hardware/gpu/intel.sh)")
            PLAN_COMMANDS+=("bash hardware/gpu/intel.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_NVIDIA_GPU" = true ] && [ -f "$distro_dir/hardware/gpu/nvidia.sh" ]; then
            PLAN_TITLES+=("Configure NVIDIA Graphics Drivers (${TARGET_DISTRO}/hardware/gpu/nvidia.sh)")
            PLAN_COMMANDS+=("bash hardware/gpu/nvidia.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_ASUS" = true ] && [ -f "$distro_dir/hardware/asus.sh" ]; then
            PLAN_TITLES+=("Configure ASUS ROG Tools (${TARGET_DISTRO}/hardware/asus.sh)")
            PLAN_COMMANDS+=("bash hardware/asus.sh ${CFG_ASUS_LIMIT}")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_TOUCHPAD" = true ] && [ -f "$distro_dir/hardware/touchpad.sh" ]; then
            PLAN_TITLES+=("Configure Precision Touchpad (${TARGET_DISTRO}/hardware/touchpad.sh)")
            PLAN_COMMANDS+=("bash hardware/touchpad.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_DESKTOP" = "kde" ] && [ -f "$distro_dir/desktop/kde.sh" ]; then
            PLAN_TITLES+=("Install KDE Plasma Desktop (${TARGET_DISTRO}/desktop/kde.sh)")
            PLAN_COMMANDS+=("bash desktop/kde.sh")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "i3" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
            PLAN_TITLES+=("Install i3 Tiling Window Manager (${TARGET_DISTRO}/desktop/tiling.sh i3)")
            PLAN_COMMANDS+=("bash desktop/tiling.sh i3")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "bspwm" ] && [ -f "$distro_dir/desktop/tiling.sh" ]; then
            PLAN_TITLES+=("Install BSPWM Tiling Window Manager (${TARGET_DISTRO}/desktop/tiling.sh bspwm)")
            PLAN_COMMANDS+=("bash desktop/tiling.sh bspwm")
            PLAN_CWDS+=("$distro_dir")
        elif [ "$CFG_DESKTOP" = "tiling" ] || [ "$CFG_DESKTOP" = "both" ]; then
            if [ -f "$distro_dir/desktop/tiling.sh" ]; then
                PLAN_TITLES+=("Install X11 Tiling Window Managers (${TARGET_DISTRO}/desktop/tiling.sh both)")
                PLAN_COMMANDS+=("bash desktop/tiling.sh both")
                PLAN_CWDS+=("$distro_dir")
            fi
        fi

        if [ "$CFG_KVM" = true ] && [ -f "$distro_dir/virt/kvm-qemu.sh" ]; then
            PLAN_TITLES+=("Setup KVM, QEMU & virt-manager (${TARGET_DISTRO}/virt/kvm-qemu.sh)")
            PLAN_COMMANDS+=("bash virt/kvm-qemu.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_VMWARE" = true ] && [ -f "$distro_dir/virt/vmware-workstation.sh" ]; then
            PLAN_TITLES+=("Install VMware Workstation (${TARGET_DISTRO}/virt/vmware-workstation.sh)")
            PLAN_COMMANDS+=("bash virt/vmware-workstation.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_DOCKER" = true ] && [ -f "$distro_dir/apps/docker.sh" ]; then
            PLAN_TITLES+=("Install Docker Engine (${TARGET_DISTRO}/apps/docker.sh)")
            PLAN_COMMANDS+=("bash apps/docker.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_CODING" = true ] && [ ${#CFG_CODING_TOOLS[@]} -gt 0 ] && [ -f "$distro_dir/apps/coding.sh" ]; then
            PLAN_TITLES+=("Install Developer Suite (${TARGET_DISTRO}/apps/coding.sh)")
            PLAN_COMMANDS+=("bash apps/coding.sh ${CFG_CODING_TOOLS[*]}")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_GAMING" = true ] && [ -f "$distro_dir/apps/gaming.sh" ]; then
            PLAN_TITLES+=("Setup Gaming Stack (${TARGET_DISTRO}/apps/gaming.sh)")
            PLAN_COMMANDS+=("bash apps/gaming.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_AIML" = true ] && [ -f "$distro_dir/apps/aiml.sh" ]; then
            PLAN_TITLES+=("Install ROCm & AI/ML Acceleration Suite (${TARGET_DISTRO}/apps/aiml.sh)")
            PLAN_COMMANDS+=("bash apps/aiml.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        if [ "$CFG_PRODUCTIVITY" = true ] && [ -f "$distro_dir/apps/productivity.sh" ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
            PLAN_TITLES+=("Install Productivity Applications (${TARGET_DISTRO}/apps/productivity.sh - ${#CFG_PROD_APPS[@]} apps)")
            PLAN_COMMANDS+=("PROD_APPS='${CFG_PROD_APPS[*]}' bash apps/productivity.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

        append_extra_scripts "$distro_dir" "$TARGET_DISTRO"

        if [ -f "$distro_dir/system/shell.sh" ]; then
            PLAN_TITLES+=("Configure Shell & Terminal Utilities (${TARGET_DISTRO}/system/shell.sh)")
            PLAN_COMMANDS+=("bash system/shell.sh")
            PLAN_CWDS+=("$distro_dir")
        fi

    # ---------------- TERMUX ----------------
    elif [ "$TARGET_DISTRO" = "termux" ]; then
        if [ -f "$distro_dir/termux.sh" ]; then
            PLAN_TITLES+=("Setup Termux Environment (termux/termux.sh)")
            PLAN_COMMANDS+=("bash termux.sh")
            PLAN_CWDS+=("$distro_dir")
        fi
        if [ "$CFG_FONTS" = true ] && [ -f "$distro_dir/system/font.sh" ]; then
            PLAN_TITLES+=("Install JetBrains Mono Font (termux/system/font.sh)")
            PLAN_COMMANDS+=("bash system/font.sh")
            PLAN_CWDS+=("$distro_dir")
        fi
        append_extra_scripts "$distro_dir" "termux"
    fi

    # Universal steps for all desktop distributions
    if [ "$TARGET_DISTRO" != "termux" ]; then
        if [ "$CFG_NVIM_CLONE" = true ]; then
            local nvim_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
            if [ ! -d "$nvim_dir" ]; then
                PLAN_TITLES+=("Clone Neovim Configuration (Aadishx07/neovim_config)")
                PLAN_COMMANDS+=("mkdir -p \"$(dirname \"$nvim_dir\")\" && git clone https://github.com/Aadishx07/neovim_config.git \"$nvim_dir\"")
                PLAN_CWDS+=("$HOME")
            fi
        fi

        PLAN_TITLES+=("Create Standard Directories (~/Pictures/Screenshots)")
        PLAN_COMMANDS+=("mkdir -p \"$HOME/Pictures/Screenshots\"")
        PLAN_CWDS+=("$HOME")
    fi
}

run_execution_plan() {
    local dry_run="${1:-false}"

    build_plan

    local total_steps=${#PLAN_TITLES[@]}
    if [ "$total_steps" -eq 0 ]; then
        log_warn "No steps planned for execution."
        return 0
    fi

    [ "$TERM" != "dumb" ] && clear 2>/dev/null || true
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
    for ((i = 0; i < total_steps; i++)); do
        printf "  %2d. %s\n" "$((i + 1))" "${PLAN_TITLES[i]}"
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

    for ((i = 0; i < total_steps; i++)); do
        local title="${PLAN_TITLES[i]}"
        local cmd="${PLAN_COMMANDS[i]}"
        local cwd="${PLAN_CWDS[i]}"
        local step_num=$((i + 1))

        echo ""
        log_step "[$step_num/$total_steps] $title"
        local step_start
        step_start=$(date +%s)
        local exit_code=0

        (
            cd "$cwd"
            eval "$cmd"
        ) || exit_code=$?

        local step_duration=$(($(date +%s) - step_start))

        if [ "$exit_code" -eq 0 ]; then
            echo -e "    ${GREEN}✓ Success (${step_duration}s)${NC}"
        else
            has_errors=true
            echo -e "    ${RED}✖ FAILED: ${title} (Exit code: ${exit_code}, ${step_duration}s)${NC}"
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
        echo -e " Check the session log for detailed diagnostics: ${LOG_FILE}"
    else
        echo -e "${GREEN}${BOLD} Installation COMPLETED SUCCESSFULLY in ${total_time}s!${NC}"
        echo -e " Please restart your session or reboot for all changes to take effect."
    fi
    echo -e "${BOLD}${CYAN}============================================================${NC}"

    if [ -c /dev/tty ] && [ "$FORCE_CLI" = false ]; then
        local tui_tool
        tui_tool=$(get_tui_tool)
        local done_msg="Post-Installation has finished!\n\nTarget Distribution: ${DISTRO_NAME}\nElapsed Time: ${total_time} seconds\nFull Log: ${LOG_FILE}\n\nPlease restart your session or reboot for all changes to take effect."
        if [ "$tui_tool" = "whiptail" ]; then
            whiptail --title "Installation Complete" --msgbox "$done_msg" 16 72 </dev/tty || true
        elif [ "$tui_tool" = "dialog" ]; then
            dialog --title "Installation Complete" --msgbox "$done_msg" 16 72 </dev/tty || true
        fi
    fi
}

# ============================================================================
# DIALOG CONFIGURATION PICKERS (Sub-screens)
# ============================================================================

picker_desktop_environment() {
    local tui_tool="$1"
    local title="Desktop Environment (${TARGET_DISTRO}/desktop/)"
    local prompt="Select desktop environment for ${DISTRO_NAME}:"

    local choice=""
    if [ "$tui_tool" = "whiptail" ]; then
        choice=$(whiptail --default-item "$CFG_DESKTOP" --title "$title" --menu "$prompt" 18 74 5 \
            "kde" "KDE Plasma Desktop (${TARGET_DISTRO}/desktop/kde.sh)" \
            "i3" "i3 Window Manager (${TARGET_DISTRO}/desktop/tiling.sh i3)" \
            "bspwm" "BSPWM + sxhkd (${TARGET_DISTRO}/desktop/tiling.sh bspwm)" \
            "both" "Both i3 & BSPWM (${TARGET_DISTRO}/desktop/tiling.sh both)" \
            "none" "None / Headless (Skip desktop setup)" \
            3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        choice=$(dialog --default-item "$CFG_DESKTOP" --no-hot-list --stdout --title "$title" --menu "$prompt" 18 74 5 \
            "kde" "KDE Plasma Desktop (${TARGET_DISTRO}/desktop/kde.sh)" \
            "i3" "i3 Window Manager (${TARGET_DISTRO}/desktop/tiling.sh i3)" \
            "bspwm" "BSPWM + sxhkd (${TARGET_DISTRO}/desktop/tiling.sh bspwm)" \
            "both" "Both i3 & BSPWM (${TARGET_DISTRO}/desktop/tiling.sh both)" \
            "none" "None / Headless (Skip desktop setup)" </dev/tty) || return 0
    fi

    if [ -n "$choice" ]; then
        CFG_DESKTOP="$choice"
    fi
}

picker_hardware() {
    local tui_tool="$1"
    local title="Hardware & Drivers (${TARGET_DISTRO}/hardware/)"
    local prompt="Toggle hardware drivers to configure:\n\n[j/k]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm"

    local items=()
    items+=("asus" "ASUS ROG Tools & Fan Curves (${TARGET_DISTRO}/hardware/asus.sh)" "$([ "$CFG_ASUS" = true ] && echo ON || echo OFF)")
    items+=("amd" "AMD CPU/GPU Drivers & Optimization (${TARGET_DISTRO}/hardware/gpu/amd.sh)" "$([ "$CFG_AMD_GPU" = true ] && echo ON || echo OFF)")
    items+=("intel" "Intel CPU/GPU Drivers (${TARGET_DISTRO}/hardware/gpu/intel.sh)" "$([ "$CFG_INTEL_GPU" = true ] && echo ON || echo OFF)")
    items+=("nvidia" "NVIDIA GPU Drivers (${TARGET_DISTRO}/hardware/gpu/nvidia.sh)" "$([ "$CFG_NVIDIA_GPU" = true ] && echo ON || echo OFF)")
    if [ -f "${TARGET_DISTRO}/hardware/touchpad.sh" ] || [ -f "arch/hardware/touchpad.sh" ]; then
        items+=("touchpad" "Precision Touchpad Configuration (${TARGET_DISTRO}/hardware/touchpad.sh)" "$([ "$CFG_TOUCHPAD" = true ] && echo ON || echo OFF)")
    fi

    local count=$(( ${#items[@]} / 3 ))
    local sel=""
    if [ "$tui_tool" = "whiptail" ]; then
        sel=$(whiptail --title "$title" --checklist "$prompt" 18 80 "$count" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        sel=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" 18 80 "$count" "${items[@]}" </dev/tty) || return 0
    fi

    has_hw() {
        local target="$1"
        [[ "$sel" =~ (^|[[:space:]]|\")"$target"($|[[:space:]]|\") ]]
    }

    CFG_ASUS=false
    CFG_AMD_GPU=false
    CFG_INTEL_GPU=false
    CFG_NVIDIA_GPU=false
    CFG_TOUCHPAD=false

    has_hw "asus" && CFG_ASUS=true
    has_hw "amd" && CFG_AMD_GPU=true
    has_hw "intel" && CFG_INTEL_GPU=true
    has_hw "nvidia" && CFG_NVIDIA_GPU=true
    has_hw "touchpad" && CFG_TOUCHPAD=true

    # 1. Prompt for AMD Pro packages when AMD GPU is selected on Arch Linux (matching core/tui/model.py)
    if [ "$CFG_AMD_GPU" = true ] && [ "$TARGET_DISTRO" = "arch" ]; then
        local pro_choice=""
        local pro_default="$([ "$CFG_AMD_PRO" = true ] && echo "yes" || echo "no")"
        local pro_title="Install AMD Pro Packages? (arch/hardware/gpu/amd.sh --pro)"
        local pro_prompt="Install proprietary AMD Pro components (AMF, OpenCL, OGLP from AUR)?"
        if [ "$tui_tool" = "whiptail" ]; then
            pro_choice=$(whiptail --default-item "$pro_default" --title "$pro_title" --menu "$pro_prompt" 14 74 2 \
                "no" "No  - Open-source Mesa stack only (Recommended)" \
                "yes" "Yes - Also install AMD Pro AUR packages (AMF, OpenCL, OGLP)" \
                3>&1 1>&2 2>&3 </dev/tty) || pro_choice="$pro_default"
        else
            pro_choice=$(dialog --default-item "$pro_default" --no-hot-list --stdout --title "$pro_title" --menu "$pro_prompt" 14 74 2 \
                "no" "No  - Open-source Mesa stack only (Recommended)" \
                "yes" "Yes - Also install AMD Pro AUR packages (AMF, OpenCL, OGLP)" </dev/tty) || pro_choice="$pro_default"
        fi
        if [ "$pro_choice" = "yes" ]; then
            CFG_AMD_PRO=true
        else
            CFG_AMD_PRO=false
        fi
    else
        CFG_AMD_PRO=false
    fi

    # 2. Prompt for ASUS battery charge limit when ASUS ROG tooling is selected
    if [ "$CFG_ASUS" = true ]; then
        # Ensure terminal cursor is fully unhidden and set to high-visibility blinking block
        printf '\033[?25h\033[?12;25h\033[1 q' >/dev/tty 2>/dev/null || tput cnorm 2>/dev/null || true

        local limit_choice=""
        local limit_title="ASUS Battery Charge Limit"
        local limit_prompt="Select battery charge threshold limit (prolongs battery health):\n\nCurrent threshold: ${CFG_ASUS_LIMIT}%"

        if [ "$tui_tool" = "whiptail" ]; then
            limit_choice=$(whiptail --default-item "$CFG_ASUS_LIMIT" --title "$limit_title" --menu "$limit_prompt" 16 72 5 \
                "85" "85% - Balanced ROG default (Recommended)" \
                "80" "80% - Extended battery longevity" \
                "60" "60% - Maximum lifespan (Stationary / Desk use)" \
                "100" "100% - Full capacity (Maximum mobile runtime)" \
                "custom" "Custom - Enter specific percentage (50-100)..." \
                3>&1 1>&2 2>&3 </dev/tty) || limit_choice="$CFG_ASUS_LIMIT"
        else
            limit_choice=$(dialog --default-item "$CFG_ASUS_LIMIT" --no-hot-list --stdout --title "$limit_title" --menu "$limit_prompt" 16 72 5 \
                "85" "85% - Balanced ROG default (Recommended)" \
                "80" "80% - Extended battery longevity" \
                "60" "60% - Maximum lifespan (Stationary / Desk use)" \
                "100" "100% - Full capacity (Maximum mobile runtime)" \
                "custom" "Custom - Enter specific percentage (50-100)..." </dev/tty) || limit_choice="$CFG_ASUS_LIMIT"
        fi

        if [ "$limit_choice" = "custom" ]; then
            local limit_str=""
            printf '\033[?25h\033[?12;25h\033[1 q' >/dev/tty 2>/dev/null || tput cnorm 2>/dev/null || true
            if [ "$tui_tool" = "whiptail" ]; then
                limit_str=$(whiptail --title "Custom ASUS Battery Limit" --inputbox "Enter battery charge threshold percentage (50-100):" 10 64 "$CFG_ASUS_LIMIT" 3>&1 1>&2 2>&3 </dev/tty) || limit_str="$CFG_ASUS_LIMIT"
            else
                limit_str=$(dialog --stdout --title "Custom ASUS Battery Limit" --inputbox "Enter battery charge threshold percentage (50-100):" 10 64 "$CFG_ASUS_LIMIT" </dev/tty) || limit_str="$CFG_ASUS_LIMIT"
            fi
            if [ -n "$limit_str" ] && [[ "$limit_str" =~ ^[0-9]+$ ]]; then
                if [ "$limit_str" -lt 50 ]; then limit_str=50; fi
                if [ "$limit_str" -gt 100 ]; then limit_str=100; fi
                CFG_ASUS_LIMIT="$limit_str"
            fi
        elif [ -n "$limit_choice" ] && [[ "$limit_choice" =~ ^[0-9]+$ ]]; then
            CFG_ASUS_LIMIT="$limit_choice"
        fi
    fi
}

picker_virtualization() {
    local tui_tool="$1"
    local title="Virtualization Setup (${TARGET_DISTRO}/virt/)"
    local prompt="Toggle virtualization components:\n\n[j/k]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm"

    local items=(
        "kvm" "KVM / QEMU & virt-manager (libvirtd network)" "$([ "$CFG_KVM" = true ] && echo ON || echo OFF)"
        "vmware" "VMware Workstation Host & Kernel Modules" "$([ "$CFG_VMWARE" = true ] && echo ON || echo OFF)"
    )

    local count=$(( ${#items[@]} / 3 ))
    local sel=""
    if [ "$tui_tool" = "whiptail" ]; then
        sel=$(whiptail --title "$title" --checklist "$prompt" 14 74 "$count" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        sel=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" 14 74 "$count" "${items[@]}" </dev/tty) || return 0
    fi

    CFG_KVM=false
    if [[ "$sel" =~ "kvm" ]]; then CFG_KVM=true; fi
    CFG_VMWARE=false
    if [[ "$sel" =~ "vmware" ]]; then CFG_VMWARE=true; fi
}

picker_coding_tools() {
    local tui_tool="$1"
    local title="Developer & Coding Suite"
    local prompt="Select coding tools to install:\n\n[j/k]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm"

    local has_neovim=OFF
    local has_vscode=OFF
    local has_cursor=OFF
    local has_claude=OFF
    local has_studio=OFF
    local has_flutter=OFF
    local has_antigravity=OFF

    for t in "${CFG_CODING_TOOLS[@]}"; do
        case "$t" in
        neovim) has_neovim=ON ;;
        vscode) has_vscode=ON ;;
        cursor) has_cursor=ON ;;
        claude_code) has_claude=ON ;;
        android_studio) has_studio=ON ;;
        flutter) has_flutter=ON ;;
        antigravity) has_antigravity=ON ;;
        esac
    done

    local items=()
    if [ "$TARGET_DISTRO" != "arch" ]; then
        items+=("neovim" "Neovim Modern Text Editor" "$has_neovim")
    fi
    items+=(
        "vscode" "Visual Studio Code" "$has_vscode"
        "cursor" "Cursor AI Code Editor" "$has_cursor"
        "claude_code" "Claude Code CLI" "$has_claude"
        "android_studio" "Android Studio" "$has_studio"
        "flutter" "Flutter SDK & Android Integration" "$has_flutter"
        "antigravity" "Antigravity CLI & IDE" "$has_antigravity"
    )

    local count=$(( ${#items[@]} / 3 ))
    local sel=""
    if [ "$tui_tool" = "whiptail" ]; then
        sel=$(whiptail --title "$title" --checklist "$prompt" 18 76 "$count" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        sel=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" 18 76 "$count" "${items[@]}" </dev/tty) || return 0
    fi

    CFG_CODING_TOOLS=()
    if [[ "$sel" =~ "neovim" ]]; then CFG_CODING_TOOLS+=("neovim"); fi
    if [[ "$sel" =~ "vscode" ]]; then CFG_CODING_TOOLS+=("vscode"); fi
    if [[ "$sel" =~ "cursor" ]]; then CFG_CODING_TOOLS+=("cursor"); fi
    if [[ "$sel" =~ "claude_code" ]]; then CFG_CODING_TOOLS+=("claude_code"); fi
    if [[ "$sel" =~ "android_studio" ]]; then CFG_CODING_TOOLS+=("android_studio"); fi
    if [[ "$sel" =~ "flutter" ]]; then CFG_CODING_TOOLS+=("flutter"); fi
    if [[ "$sel" =~ "antigravity" ]]; then CFG_CODING_TOOLS+=("antigravity"); fi

    if [ ${#CFG_CODING_TOOLS[@]} -gt 0 ]; then
        CFG_CODING=true
    else
        CFG_CODING=false
    fi
}

picker_productivity() {
    local tui_tool="$1"
    local title="Productivity & Browsers"
    local prompt="Select productivity tools & browsers to install:\n\n[j/k]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm"

    local has_thorium=OFF
    local has_zen=OFF
    local has_vesktop=OFF
    local has_localsend=OFF
    local has_anydesk=OFF
    local has_obsidian=OFF
    local has_markitdown=OFF
    local has_gallery_dl=OFF
    local has_ani_cli=OFF
    local has_advcpmv=OFF

    for p in "${CFG_PROD_APPS[@]}"; do
        case "$p" in
        thorium) has_thorium=ON ;;
        zen) has_zen=ON ;;
        vesktop) has_vesktop=ON ;;
        localsend) has_localsend=ON ;;
        anydesk) has_anydesk=ON ;;
        obsidian) has_obsidian=ON ;;
        markitdown) has_markitdown=ON ;;
        gallery_dl) has_gallery_dl=ON ;;
        ani_cli) has_ani_cli=ON ;;
        advcpmv) has_advcpmv=ON ;;
        esac
    done

    local items=(
        "thorium" "Thorium Browser (Optimized Chromium fork)" "$has_thorium"
        "zen" "Zen Browser (Gecko privacy browser)" "$has_zen"
        "vesktop" "Vesktop Discord Client (Wayland & Vencord)" "$has_vesktop"
        "localsend" "LocalSend (AirDrop alternative)" "$has_localsend"
        "anydesk" "AnyDesk (Remote desktop client)" "$has_anydesk"
        "obsidian" "Obsidian (Markdown notes & knowledge base)" "$has_obsidian"
        "markitdown" "MarkItDown (Document converter)" "$has_markitdown"
        "gallery_dl" "gallery-dl (Image batch downloader)" "$has_gallery_dl"
        "ani_cli" "ani-cli (Anime streaming CLI)" "$has_ani_cli"
    )
    if [ "$TARGET_DISTRO" = "arch" ]; then
        items+=("advcpmv" "advcpmv (cp/mv with progress bars)" "$has_advcpmv")
    fi

    local count=$(( ${#items[@]} / 3 ))
    local sel=""
    if [ "$tui_tool" = "whiptail" ]; then
        sel=$(whiptail --title "$title" --checklist "$prompt" 21 78 "$count" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        sel=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" 21 78 "$count" "${items[@]}" </dev/tty) || return 0
    fi

    CFG_PROD_APPS=()
    if [[ "$sel" =~ "thorium" ]]; then CFG_PROD_APPS+=("thorium"); fi
    if [[ "$sel" =~ "zen" ]]; then CFG_PROD_APPS+=("zen"); fi
    if [[ "$sel" =~ "vesktop" ]]; then CFG_PROD_APPS+=("vesktop"); fi
    if [[ "$sel" =~ "localsend" ]]; then CFG_PROD_APPS+=("localsend"); fi
    if [[ "$sel" =~ "anydesk" ]]; then CFG_PROD_APPS+=("anydesk"); fi
    if [[ "$sel" =~ "obsidian" ]]; then CFG_PROD_APPS+=("obsidian"); fi
    if [[ "$sel" =~ "markitdown" ]]; then CFG_PROD_APPS+=("markitdown"); fi
    if [[ "$sel" =~ "gallery_dl" ]]; then CFG_PROD_APPS+=("gallery_dl"); fi
    if [[ "$sel" =~ "ani_cli" ]]; then CFG_PROD_APPS+=("ani_cli"); fi
    if [[ "$sel" =~ "advcpmv" ]]; then CFG_PROD_APPS+=("advcpmv"); fi

    if [ ${#CFG_PROD_APPS[@]} -gt 0 ]; then
        CFG_PRODUCTIVITY=true
    else
        CFG_PRODUCTIVITY=false
    fi
}

picker_aur_helper() {
    local tui_tool="$1"
    local title="AUR Helper Selection (arch/apps/)"
    local prompt="Choose the AUR helper to install:"

    local choice=""
    if [ "$tui_tool" = "whiptail" ]; then
        choice=$(whiptail --default-item "$CFG_AUR" --title "$title" --menu "$prompt" 16 70 4 \
            "paru" "Paru (Modern Rust-based AUR helper, Recommended)" \
            "yay" "Yay (Classic Go-based AUR helper)" \
            "both" "Both (Install Paru & Yay side-by-side)" \
            "none" "None (Skip AUR helper installation)" \
            3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        choice=$(dialog --default-item "$CFG_AUR" --no-hot-list --stdout --title "$title" --menu "$prompt" 16 70 4 \
            "paru" "Paru (Modern Rust-based AUR helper, Recommended)" \
            "yay" "Yay (Classic Go-based AUR helper)" \
            "both" "Both (Install Paru & Yay side-by-side)" \
            "none" "None (Skip AUR helper installation)" </dev/tty) || return 0
    fi

    if [ -n "$choice" ]; then
        CFG_AUR="$choice"
    fi
}

picker_distro() {
    local tui_tool="$1"
    local title="Select Distribution / Target OS"
    local prompt="Select active distribution workspace folder:"

    local choice=""
    if [ "$tui_tool" = "whiptail" ]; then
        choice=$(whiptail --default-item "$TARGET_DISTRO" --title "$title" --menu "$prompt" 18 70 5 \
            "arch" "Arch Linux (arch/ modular folder)" \
            "debian" "Debian / Ubuntu (debian/ modular folder)" \
            "fedora" "Fedora (fedora/ modular folder)" \
            "kali" "Kali Linux (kali/ modular folder)" \
            "termux" "Termux (termux/ modular folder)" \
            3>&1 1>&2 2>&3 </dev/tty) || return 0
    else
        choice=$(dialog --default-item "$TARGET_DISTRO" --no-hot-list --stdout --title "$title" --menu "$prompt" 18 70 5 \
            "arch" "Arch Linux (arch/ modular folder)" \
            "debian" "Debian / Ubuntu (debian/ modular folder)" \
            "fedora" "Fedora (fedora/ modular folder)" \
            "kali" "Kali Linux (kali/ modular folder)" \
            "termux" "Termux (termux/ modular folder)" </dev/tty) || return 0
    fi

    if [ -n "$choice" ]; then
        TARGET_DISTRO="$choice"
        set_distro_defaults
    fi
}

# ============================================================================
# ARCHINSTALL GLOBAL MENU (Pure Bash replica of model.py & screens.py)
# Displays configured state right on the menu item, exactly like Archinstall.
# ============================================================================
run_tui() {
    local tui_tool
    tui_tool=$(get_tui_tool)

    if [ "$tui_tool" = "none" ]; then
        log_warn "Neither 'dialog' nor 'whiptail' found. Falling back to CLI mode."
        run_cli_interactive
        return
    fi

    if [ "$tui_tool" = "dialog" ]; then
        setup_vim_keybindings
    fi

    # Ensure cursor is visible
    printf '\033[?25h\033[1 q' >/dev/tty 2>/dev/null || tput cnorm 2>/dev/null || true

    local current_item="distro"

    while true; do
        # Format live values for display badges (matching model.py)
        local val_distro="[${TARGET_DISTRO^^}] ${DISTRO_NAME}"
        local val_desktop="[NONE]"
        case "$CFG_DESKTOP" in
        kde) val_desktop="[KDE]" ;;
        i3) val_desktop="[i3]" ;;
        bspwm) val_desktop="[BSPWM]" ;;
        both | tiling) val_desktop="[i3 + BSPWM]" ;;
        none | *) val_desktop="[NONE]" ;;
        esac

        local hw_tags=()
        if [ "$CFG_ASUS" = true ]; then hw_tags+=("ASUS (${CFG_ASUS_LIMIT}%)"); fi
        if [ "$CFG_AMD_GPU" = true ]; then
            if [ "$TARGET_DISTRO" = "arch" ] && [ "$CFG_AMD_PRO" = true ]; then
                hw_tags+=("AMD + Pro")
            else
                hw_tags+=("AMD")
            fi
        fi
        if [ "$CFG_INTEL_GPU" = true ]; then hw_tags+=("Intel"); fi
        if [ "$CFG_NVIDIA_GPU" = true ]; then hw_tags+=("NVIDIA"); fi
        if [ "$CFG_TOUCHPAD" = true ]; then hw_tags+=("Touchpad"); fi
        local val_hardware="[None]"
        if [ ${#hw_tags[@]} -gt 0 ]; then
            local hw_str=""
            for tag in "${hw_tags[@]}"; do
                [ -n "$hw_str" ] && hw_str+=", "
                hw_str+="$tag"
            done
            val_hardware="[${hw_str}]"
        fi

        local virt_tags=()
        if [ "$CFG_KVM" = true ]; then virt_tags+=("KVM/QEMU"); fi
        if [ "$CFG_VMWARE" = true ]; then virt_tags+=("VMware"); fi
        local val_virt="[None]"
        if [ ${#virt_tags[@]} -gt 0 ]; then
            local virt_str=""
            for tag in "${virt_tags[@]}"; do
                [ -n "$virt_str" ] && virt_str+=", "
                virt_str+="$tag"
            done
            val_virt="[${virt_str}]"
        fi

        local val_docker="$([ "$CFG_DOCKER" = true ] && echo "[Yes]" || echo "[No]")"
        local val_coding="[$([ "$CFG_CODING" = true ] && echo "${#CFG_CODING_TOOLS[@]} tools" || echo "No")]"
        local val_burp="$([ "$CFG_SECURITY_BURP" = true ] && echo "[Yes]" || echo "[No]")"
        local val_gaming="$([ "$CFG_GAMING" = true ] && echo "[Yes]" || echo "[No]")"
        local val_aiml="$([ "$CFG_AIML" = true ] && echo "[Yes]" || echo "[No]")"
        local val_aur="[${CFG_AUR^^}]"
        local val_mirrors="$([ "$CFG_MIRRORS" = true ] && echo "[Yes (India)]" || echo "[No]")"
        local val_prod="[$([ "$CFG_PRODUCTIVITY" = true ] && [ ${#CFG_PROD_APPS[@]} -gt 0 ] && echo "${#CFG_PROD_APPS[@]} apps" || echo "No")]"

        local menu_title="Post-Installation Automation Suite (Archinstall TUI)"
        local menu_prompt="Host: ${SYS_HOSTNAME} (${CPU_VENDOR}) | OS Folder: ./${TARGET_DISTRO}/ | User: ${SYS_USER}\n\n[j/k]=Navigate  [ENTER]=Select/Toggle  [h/l]=Buttons"

        # Construct menu items based on distribution (strictly mirrors model.py)
        local menu_items=()
        add_menu_row() {
            local tag="$1"
            local label="$2"
            local value="$3"
            local formatted
            printf -v formatted "%-42s %s" "$label" "$value"
            menu_items+=("$tag" "$formatted")
        }

        add_menu_row "distro" "Distribution / Target OS" "${val_distro}"

        if [ "$TARGET_DISTRO" = "arch" ]; then
            add_menu_row "desktop" "Desktop Environment" "${val_desktop}"
            add_menu_row "hardware" "Hardware & Drivers (arch/hardware/)" "${val_hardware}"
            add_menu_row "virt" "Virtualization (arch/virt/)" "${val_virt}"
            add_menu_row "docker" "Docker Engine & Buildx" "${val_docker}"
            add_menu_row "coding" "Developer Tools (AUR)" "${val_coding}"
            add_menu_row "burp" "Burp Suite Professional" "${val_burp}"
            add_menu_row "gaming" "Gaming Stack & Wine" "${val_gaming}"
            add_menu_row "aiml" "AI / ML Acceleration (ROCm)" "${val_aiml}"
            add_menu_row "prod" "Productivity & Browsers (AUR)" "${val_prod}"
            add_menu_row "aur" "AUR Helper Selection" "${val_aur}"
            add_menu_row "mirrors" "Mirror Optimization (Reflector India)" "${val_mirrors}"
        elif [ "$TARGET_DISTRO" = "kali" ]; then
            add_menu_row "burp" "Burp Suite Professional" "${val_burp}"
            add_menu_row "kali_meta" "Kali Metapackages" "[${CFG_KALI_META}]"
            add_menu_row "wifi" "Realtek WiFi Driver (RTL8821AU)" "$([ "$CFG_KALI_WIFI" = true ] && echo "[Yes]" || echo "[No]")"
            add_menu_row "docker" "Docker CE Engine" "${val_docker}"
        elif [ "$TARGET_DISTRO" = "debian" ] || [ "$TARGET_DISTRO" = "fedora" ]; then
            add_menu_row "desktop" "Desktop Environment" "${val_desktop}"
            add_menu_row "hardware" "Hardware & Drivers" "${val_hardware}"
            add_menu_row "virt" "Virtualization" "${val_virt}"
            add_menu_row "docker" "Docker Engine" "${val_docker}"
            add_menu_row "coding" "Developer Suite" "${val_coding}"
            add_menu_row "gaming" "Gaming Stack" "${val_gaming}"
            add_menu_row "aiml" "AI / ML Acceleration (ROCm)" "${val_aiml}"
            add_menu_row "prod" "Productivity Applications" "${val_prod}"
        elif [ "$TARGET_DISTRO" = "termux" ]; then
            add_menu_row "termux_core" "Termux Environment Setup" "[Yes]"
            add_menu_row "fonts" "JetBrains Mono Nerd Font" "$([ "$CFG_FONTS" = true ] && echo "[Yes]" || echo "[No]")"
        fi

        add_menu_row "install" "--> Install" "[Start post-installation]"
        add_menu_row "abort" "--> Abort" "[Exit installer]"

        # Ensure current_item exists in the current menu_items list; if not, default to "distro"
        local item_exists=false
        for ((m = 0; m < ${#menu_items[@]}; m += 2)); do
            if [ "${menu_items[m]}" = "$current_item" ]; then
                item_exists=true
                break
            fi
        done
        if [ "$item_exists" = false ]; then
            current_item="distro"
        fi

        local num_items=$(( ${#menu_items[@]} / 2 ))
        local box_height=$(( num_items + 9 ))
        [ "$box_height" -lt 24 ] && box_height=24

        local choice=""
        local exit_code=0
        if [ "$tui_tool" = "whiptail" ]; then
            choice=$(whiptail --default-item "$current_item" --title "$menu_title" --menu "$menu_prompt" "$box_height" 84 "$num_items" "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || exit_code=$?
        else
            choice=$(dialog --default-item "$current_item" --no-hot-list --stdout --title "$menu_title" --menu "$menu_prompt" "$box_height" 84 "$num_items" "${menu_items[@]}" </dev/tty) || exit_code=$?
        fi

        if [ "$exit_code" -ne 0 ]; then
            choice="abort"
        fi

        if [ -n "$choice" ] && [ "$choice" != "abort" ] && [ "$choice" != "install" ]; then
            current_item="$choice"
        fi

        case "$choice" in
        distro) picker_distro "$tui_tool" ;;
        desktop) picker_desktop_environment "$tui_tool" ;;
        hardware) picker_hardware "$tui_tool" ;;
        virt) picker_virtualization "$tui_tool" ;;
        coding) picker_coding_tools "$tui_tool" ;;
        prod) picker_productivity "$tui_tool" ;;
        aur) picker_aur_helper "$tui_tool" ;;

        # Direct quick toggles (Space/Enter flips in place)
        docker)
            if [ "$CFG_DOCKER" = true ]; then CFG_DOCKER=false; else CFG_DOCKER=true; fi
            ;;
        burp)
            if [ "$CFG_SECURITY_BURP" = true ]; then CFG_SECURITY_BURP=false; else CFG_SECURITY_BURP=true; fi
            ;;
        gaming)
            if [ "$CFG_GAMING" = true ]; then CFG_GAMING=false; else CFG_GAMING=true; fi
            ;;
        aiml)
            if [ "$CFG_AIML" = true ]; then CFG_AIML=false; else CFG_AIML=true; fi
            ;;
        mirrors)
            if [ "$CFG_MIRRORS" = true ]; then CFG_MIRRORS=false; else CFG_MIRRORS=true; fi
            ;;
        wifi)
            if [ "$CFG_KALI_WIFI" = true ]; then CFG_KALI_WIFI=false; else CFG_KALI_WIFI=true; fi
            ;;
        fonts)
            if [ "$CFG_FONTS" = true ]; then CFG_FONTS=false; else CFG_FONTS=true; fi
            ;;
        kali_meta)
            local m_choice=""
            if [ "$tui_tool" = "whiptail" ]; then
                m_choice=$(whiptail --default-item "$CFG_KALI_META" --title "Kali Metapackages" --menu "Select suite:" 14 60 3 \
                    "large" "kali-linux-large (Recommended)" \
                    "everything" "kali-linux-everything" \
                    "default" "kali-linux-default" 3>&1 1>&2 2>&3 </dev/tty) || true
            else
                m_choice=$(dialog --default-item "$CFG_KALI_META" --no-hot-list --stdout --title "Kali Metapackages" --menu "Select suite:" 14 60 3 \
                    "large" "kali-linux-large (Recommended)" \
                    "everything" "kali-linux-everything" \
                    "default" "kali-linux-default" </dev/tty) || true
            fi
            if [ -n "$m_choice" ]; then CFG_KALI_META="$m_choice"; fi
            ;;

        install)
            # Confirm before running
            build_plan
            local plan_msg="Ready to execute ./${TARGET_DISTRO}/ post-installation plan (${#PLAN_TITLES[@]} steps).\n\nTarget OS: ${DISTRO_NAME}\nSession Log: ${LOG_FILE}\n\nStart installation now?"
            local do_run=false
            if [ "$tui_tool" = "whiptail" ]; then
                if whiptail --title "Confirm Installation" --yesno "$plan_msg" 14 72 3>&1 1>&2 2>&3 </dev/tty; then
                    do_run=true
                fi
            else
                if dialog --title "Confirm Installation" --yesno "$plan_msg" 14 72 </dev/tty; then
                    do_run=true
                fi
            fi

            if [ "$do_run" = true ]; then
                run_execution_plan false
                break
            fi
            ;;

        abort | "")
            local confirm_exit=false
            if [ "$tui_tool" = "whiptail" ]; then
                if whiptail --title "Exit Installer?" --yesno "Are you sure you want to exit without applying changes?" 10 64 3>&1 1>&2 2>&3 </dev/tty; then
                    confirm_exit=true
                fi
            else
                if dialog --title "Exit Installer?" --yesno "Are you sure you want to exit without applying changes?" 10 64 </dev/tty; then
                    confirm_exit=true
                fi
            fi

            if [ "$confirm_exit" = true ]; then
                [ "$TERM" != "dumb" ] && clear 2>/dev/null || true
                log_info "Exiting Post-Installation Suite. Have a productive day!"
                break
            fi
            ;;
        esac
    done
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

# TUI is default when interactive
if [ -t 0 ] && [ -t 1 ]; then
    run_tui
else
    run_execution_plan false
fi
