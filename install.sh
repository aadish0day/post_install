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
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/menu.sh
source "$SCRIPT_DIR/lib/menu.sh"

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
    debian) managed=("docker" "lazydocker" "neovim" "coding" "gaming" "aiml" "productivity" "markitdown" "xdm") ;;
    fedora) managed=("docker" "lazydocker" "coding" "gaming" "aiml" "productivity" "markitdown" "xdm") ;;
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
        PLAN_COMMANDS+=("sudo pacman -S --needed --noconfirm --overwrite '*' android-tools aria2 atool bat chromaprint doxygen duf fastfetch fd fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly highlight htop img2pdf imagemagick inxi jq jpegoptim less libavtp libdca libgme liblrdf libltc libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv ncdu neovim nodejs npm obs-studio 7zip pacman-contrib pacutils parallel pipewire pipewire-alsa pipewire-audio pipewire-jack lib32-pipewire-jack pipewire-pulse pipewire-zeroconf pipewire-libcamera rtkit pkgfile plocate pv ripgrep sd spandsp starship soundtouch svt-hevc tar tree tree-sitter-cli trash-cli tmux unzip wireplumber xz yazi yt-dlp zip zoxide zsh zstd dosfstools usbutils lazydocker opencode github-cli && if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then git lfs install --skip-repo; fi")
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
        PLAN_COMMANDS+=("sudo systemctl enable --now rtkit-daemon.service 2>/dev/null || true; for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do if systemctl --user list-unit-files 2>/dev/null | grep -q \"\$s\"; then systemctl --user start \"\$s\" 2>/dev/null || true; fi; done; if [ \"\$SHELL\" != \"\$(command -v zsh 2>/dev/null || echo '')\" ] && command -v zsh &>/dev/null; then chsh -s \"\$(command -v zsh)\" \"\$USER\" 2>/dev/null || true; fi")
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

            if [ -f "$distro_dir/apps/lazydocker.sh" ]; then
                PLAN_TITLES+=("Install lazydocker TUI (${TARGET_DISTRO}/apps/lazydocker.sh)")
                PLAN_COMMANDS+=("bash apps/lazydocker.sh")
                PLAN_CWDS+=("$distro_dir")
            fi
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

            local has_xdm=false
            for p in "${CFG_PROD_APPS[@]}"; do
                if [ "$p" = "xdm" ]; then has_xdm=true; break; fi
            done
            if [ "$has_xdm" = true ] && [ -f "$distro_dir/apps/xdm.sh" ]; then
                PLAN_TITLES+=("Install XDM Download Manager (${TARGET_DISTRO}/apps/xdm.sh)")
                PLAN_COMMANDS+=("bash apps/xdm.sh")
                PLAN_CWDS+=("$distro_dir")
            fi
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
        local done_msg="Post-Installation has finished!\n\nTarget Distribution: ${DISTRO_NAME}\nElapsed Time: ${total_time} seconds\nFull Log: ${LOG_FILE}\n\nPlease restart your session or reboot for all changes to take effect."
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
