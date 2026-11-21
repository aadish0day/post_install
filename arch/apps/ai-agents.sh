#!/usr/bin/env bash
# ============================================================================
# ARCH LINUX AI CODING AGENTS INSTALLER
# Inspired by Omarchy's AI Stack (omarchy/manual/17-ai.md)
#
# Provides easy, modular installation of the top AI developer tools:
#   1. Claude Code           (claude-code via AUR)
#   2. OpenCode              (opencode / opencode-bin via pacman / AUR / binary)
#   3. Google Antigravity CLI(agy / antigravity-cli / @google/antigravity-cli)
#   4. Ollama                (official repo + AMD ROCm / NVIDIA CUDA acceleration + systemd)
# ============================================================================

set -euo pipefail

# --- Color formatting helpers ---
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    BOLD=''
    CYAN=''
    YELLOW=''
    RED=''
    GREEN=''
    BLUE=''
    NC=''
fi

# --- Logging helpers with timestamps ---
log() {
    printf "%b %b[INFO]%b %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$BLUE" "$NC" "$*"
}

success() {
    printf "%b %b[SUCCESS]%b %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$GREEN" "$NC" "$*"
}

warn() {
    printf "%b %b[WARN]%b %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$YELLOW" "$NC" "$*" >&2
}

err() {
    printf "%b %b[ERROR]%b %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$RED" "$NC" "$*" >&2
}

die() {
    err "$*"
    exit 1
}

# --- State variables ---
DO_CLAUDE=false
DO_OPENCODE=false
DO_AGY=false
DO_OLLAMA=false
FORCE=false
AUR_HELPER=""

# --- Sudo sanity check ---
check_user() {
    if [ "$EUID" -eq 0 ]; then
        warn "Running directly as root is not recommended for AUR operations and user-level node environments."
        warn "Prefer executing as a standard user with sudo privileges."
    fi
}

# --- Detect AUR helper (paru or yay) ---
detect_aur_helper() {
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    fi

    if [ -n "$AUR_HELPER" ]; then
        log "Detected AUR helper: ${BOLD}${AUR_HELPER}${NC}"
    else
        warn "No AUR helper (paru or yay) found on this system."
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$script_dir/paru.sh" ]; then
            log "Found local paru-bin installer at $script_dir/paru.sh."
            if [[ -t 0 ]]; then
                read -rp "Would you like to run paru.sh to install paru now? [Y/n]: " ans
                if [[ "$ans" =~ ^[Yy]?$ ]]; then
                    bash "$script_dir/paru.sh"
                    if command -v paru &>/dev/null; then
                        AUR_HELPER="paru"
                        success "Paru successfully installed!"
                    fi
                fi
            fi
        fi
    fi
}

# --- Detect hardware GPU acceleration for LLM inference ---
detect_gpu_acceleration() {
    local lspci_out
    lspci_out="$(lspci 2>/dev/null || true)"

    if echo "$lspci_out" | grep -Ei "vga|3d controller|display" | grep -qi "nvidia" || \
       command -v nvidia-smi &>/dev/null || [ -d /proc/driver/nvidia ]; then
        echo "nvidia"
    elif echo "$lspci_out" | grep -Ei "vga|3d controller|display" | grep -qiE "\[amd/ati\]|radeon|navi" || \
         [ -d /sys/module/amdgpu ]; then
        echo "amd"
    elif echo "$lspci_out" | grep -Ei "vga|3d controller|display" | grep -qi "intel"; then
        echo "intel"
    else
        echo "cpu"
    fi
}

# --- Prerequisites check (Node.js, npm, curl, git) ---
check_prerequisites() {
    log "Checking base system prerequisites..."

    local missing_base=()
    command -v curl &>/dev/null || missing_base+=("curl")
    command -v git &>/dev/null || missing_base+=("git")

    if [ ${#missing_base[@]} -gt 0 ]; then
        log "Installing required core tools: ${missing_base[*]}..."
        sudo pacman -S --needed --noconfirm "${missing_base[@]}"
    fi

    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
        log "Node.js or npm is missing. Installing nodejs and npm via pacman..."
        sudo pacman -S --needed --noconfirm nodejs npm
        success "Installed Node.js ($(node --version 2>/dev/null || echo 'active')) and npm ($(npm --version 2>/dev/null || echo 'active'))."
    else
        log "Prerequisites verified: Node.js ($(node --version 2>/dev/null || echo 'active')), npm ($(npm --version 2>/dev/null || echo 'active')), curl, git."
    fi

    detect_aur_helper
}

# --- Helper: npm global installer with permission check ---
npm_install_global() {
    local pkg="$1"
    local npm_prefix
    npm_prefix="$(npm config get prefix 2>/dev/null || echo "/usr")"

    log "Installing npm package globally: $pkg..."
    if [ -w "$npm_prefix" ] || [ -w "$npm_prefix/lib/node_modules" ] || [ -w "$npm_prefix/bin" ]; then
        npm install -g "$pkg"
    else
        sudo npm install -g "$pkg"
    fi
}

# --- Installer: Claude Code ---
install_claude() {
    echo ""
    log "=========================================================="
    log "Installing / Updating: Claude Code (claude-code via AUR)"
    log "=========================================================="

    if command -v claude &>/dev/null; then
        local ver
        ver="$(claude --version 2>/dev/null || echo 'installed')"
        if [ "$FORCE" = false ]; then
            log "Claude Code is already present: $ver (use -f/--force to reinstall)."
            return 0
        else
            log "Claude Code found ($ver), but --force specified. Proceeding with reinstall..."
        fi
    fi

    local install_ok=false

    # Method 1: AUR helper (paru or yay)
    if [ -n "$AUR_HELPER" ]; then
        log "Installing claude-code from AUR using $AUR_HELPER..."
        if "$AUR_HELPER" -S --needed --noconfirm claude-code; then
            install_ok=true
        else
            warn "AUR helper ($AUR_HELPER) installation failed. Attempting makepkg build..."
        fi
    fi

    # Method 2: Direct makepkg from AUR if no AUR helper or helper failed
    if [ "$install_ok" = false ]; then
        log "Building claude-code directly from AUR repository (makepkg)..."
        local tmp_build_dir
        tmp_build_dir="$(mktemp -d /tmp/claude_aur_XXXXXX)"
        if git clone --depth 1 https://aur.archlinux.org/claude-code.git "$tmp_build_dir"; then
            local target_user="${SUDO_USER:-$USER}"
            if [ "$target_user" != "root" ] && id "$target_user" &>/dev/null; then
                chown -R "$target_user:$target_user" "$tmp_build_dir"
                if sudo -u "$target_user" bash -c "cd '$tmp_build_dir' && makepkg -si --noconfirm --needed"; then
                    install_ok=true
                fi
            else
                if (cd "$tmp_build_dir" && makepkg -si --noconfirm --needed); then
                    install_ok=true
                fi
            fi
        fi
        rm -rf "$tmp_build_dir"
    fi

    if command -v claude &>/dev/null; then
        success "Claude Code installed successfully from AUR: $(claude --version 2>/dev/null || echo 'active')!"
        log "Run 'claude' in any project directory to launch."
    elif [ "$install_ok" = true ]; then
        success "Claude Code installation completed."
    else
        die "Failed to install Claude Code from AUR."
    fi
}

# --- Installer: OpenCode ---
install_opencode() {
    echo ""
    log "=========================================================="
    log "Installing / Updating: OpenCode (opencode / opencode-bin)"
    log "=========================================================="

    if command -v opencode &>/dev/null; then
        local ver
        ver="$(opencode --version 2>/dev/null || echo 'installed')"
        if [ "$FORCE" = false ]; then
            log "OpenCode is already present: $ver (use -f/--force to reinstall)."
            return 0
        else
            log "OpenCode found ($ver), but --force specified. Proceeding with reinstall..."
        fi
    fi

    local install_ok=false

    # Method 1: Arch official extra repository
    if pacman -Si opencode &>/dev/null; then
        log "Found 'opencode' in Arch official repository. Installing via pacman..."
        if sudo pacman -S --needed --noconfirm opencode; then
            install_ok=true
        fi
    fi

    # Method 2: AUR helper (opencode-bin or opencode)
    if [ "$install_ok" = false ] && [ -n "$AUR_HELPER" ]; then
        log "Attempting installation via AUR helper ($AUR_HELPER)..."
        if "$AUR_HELPER" -S --needed --noconfirm opencode-bin 2>/dev/null || \
           "$AUR_HELPER" -S --needed --noconfirm opencode; then
            install_ok=true
        fi
    fi

    # Method 3: GitHub releases direct binary download
    if [ "$install_ok" = false ]; then
        log "Attempting installation via GitHub releases (anomalyco/opencode)..."
        local arch_name="amd64"
        local uname_m
        uname_m="$(uname -m)"
        if [ "$uname_m" = "aarch64" ]; then
            arch_name="arm64"
        fi

        local release_json
        release_json="$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null || true)"
        local download_url
        download_url="$(echo "$release_json" | grep -oE "https://github\.com/anomalyco/opencode/releases/download/[^\"]+linux-${arch_name}\.tar\.gz" | head -n1 || true)"

        if [ -n "$download_url" ]; then
            local tmp_dir
            tmp_dir="$(mktemp -d /tmp/opencode_XXXXXX)"
            curl -fsSL "$download_url" | tar -xz -C "$tmp_dir"
            sudo install -Dm755 "$tmp_dir/opencode" /usr/local/bin/opencode
            rm -rf "$tmp_dir"
            install_ok=true
        fi
    fi

    if command -v opencode &>/dev/null; then
        success "OpenCode installed successfully: $(opencode --version 2>/dev/null || echo 'active')!"
        log "Run 'opencode' in your project to start."
    else
        die "Failed to install OpenCode."
    fi
}

# --- Installer: Google Antigravity CLI (agy) ---
install_agy() {
    echo ""
    log "=========================================================="
    log "Installing / Updating: Google Antigravity CLI (agy)"
    log "=========================================================="

    if command -v agy &>/dev/null; then
        local ver
        ver="$(agy --version 2>/dev/null || echo 'installed')"
        if [ "$FORCE" = false ]; then
            log "Google Antigravity CLI (agy) is already present: $ver (use -f/--force to reinstall)."
            return 0
        else
            log "Google Antigravity CLI found ($ver), but --force specified. Proceeding with reinstall..."
        fi
    fi

    local install_ok=false

    # Method 1: AUR helper (antigravity-cli package provides agy)
    if [ -n "$AUR_HELPER" ]; then
        log "Installing antigravity-cli via AUR helper ($AUR_HELPER)..."
        if "$AUR_HELPER" -S --needed --noconfirm antigravity-cli; then
            install_ok=true
        fi
    fi

    # Method 2: npm fallback (@google/antigravity-cli)
    if [ "$install_ok" = false ]; then
        log "Attempting installation via npm (@google/antigravity-cli)..."
        if npm_install_global "@google/antigravity-cli" 2>/dev/null || \
           npm_install_global "antigravity-cli" 2>/dev/null; then
            install_ok=true
        fi
    fi

    # Method 3: Standalone Google Cloud storage binary
    if [ "$install_ok" = false ]; then
        log "Attempting download of official Antigravity CLI binary..."
        local uname_m
        uname_m="$(uname -m)"
        local arch_url="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.11-6132547114106880/linux-x64/cli_linux_x64.tar.gz"
        if [ "$uname_m" = "aarch64" ]; then
            arch_url="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.11-6132547114106880/linux-arm/cli_linux_arm64.tar.gz"
        fi

        local tmp_dir
        tmp_dir="$(mktemp -d /tmp/agy_install_XXXXXX)"
        if curl -fsSL "$arch_url" | tar -xz -C "$tmp_dir" 2>/dev/null; then
            local bin_file
            bin_file="$(find "$tmp_dir" -type f \( -name "antigravity" -o -name "agy" \) 2>/dev/null | head -n1 || true)"
            if [ -n "$bin_file" ]; then
                sudo install -Dm755 "$bin_file" /usr/local/bin/agy
                install_ok=true
            fi
        fi
        rm -rf "$tmp_dir"
    fi

    if command -v agy &>/dev/null; then
        success "Google Antigravity CLI (agy) installed successfully: $(agy --version 2>/dev/null || echo 'active')!"
        log "Run 'agy' to interact with Google's agentic platform."
    else
        die "Failed to install Google Antigravity CLI (agy)."
    fi
}

# --- Installer: Ollama & Acceleration ---
install_ollama() {
    echo ""
    log "=========================================================="
    log "Installing / Updating: Ollama (Local LLM Server & Acceleration)"
    log "=========================================================="

    local gpu_type
    gpu_type="$(detect_gpu_acceleration)"
    local target_pkg="ollama"

    case "$gpu_type" in
        nvidia)
            log "Detected: ${BOLD}NVIDIA GPU${NC}. Selecting CUDA acceleration package: ${CYAN}ollama-cuda${NC}"
            target_pkg="ollama-cuda"
            ;;
        amd)
            log "Detected: ${BOLD}AMD GPU${NC}. Selecting ROCm acceleration package: ${CYAN}ollama-rocm${NC}"
            target_pkg="ollama-rocm"
            ;;
        intel)
            log "Detected: ${BOLD}Intel GPU${NC}. Selecting standard ${CYAN}ollama${NC} package (supports Vulkan acceleration)"
            target_pkg="ollama"
            ;;
        *)
            log "Detected: ${BOLD}CPU / Generic${NC}. Selecting standard ${CYAN}ollama${NC} package"
            target_pkg="ollama"
            ;;
    esac

    local need_install=true
    if command -v ollama &>/dev/null; then
        local ver
        ver="$(ollama --version 2>/dev/null || echo 'installed')"
        if [ "$FORCE" = false ]; then
            log "Ollama is already present: $ver."
            # Check if GPU acceleration package is installed when GPU is detected
            if [ "$target_pkg" != "ollama" ] && ! pacman -Qq "$target_pkg" &>/dev/null; then
                log "GPU acceleration package '$target_pkg' is not yet installed. Upgrading Ollama..."
                need_install=true
            else
                need_install=false
            fi
        else
            log "Ollama found ($ver), but --force specified. Reinstalling..."
        fi
    fi

    if [ "$need_install" = true ]; then
        log "Installing $target_pkg from Arch Linux official repositories..."
        sudo pacman -S --needed --noconfirm "$target_pkg"

        # For AMD GPUs, configure video and render group permissions for ROCm
        if [ "$gpu_type" = "amd" ]; then
            log "Ensuring user ($USER) is in video and render groups for AMD ROCm..."
            sudo usermod -aG video,render "$USER" 2>/dev/null || true
        fi
    fi

    # Enable and start Ollama systemd daemon
    log "Configuring systemd service (ollama.service)..."
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable --now ollama.service

    if systemctl is-active --quiet ollama.service 2>/dev/null; then
        success "Ollama systemd service is active and running!"
    else
        warn "Ollama service enabled, but systemctl reports not active. Check: systemctl status ollama.service"
    fi

    success "Ollama installation and service configuration complete!"
    log "Quick test: run 'ollama run qwen2.5-coder:1.5b' or 'ollama list'."
}

# --- Interactive Menu (Full TUI via dialog / whiptail) ---
interactive_menu() {
    # If dialog is available and running in a terminal, launch full TUI checklist
    if command -v dialog &>/dev/null && [ -t 0 ]; then
        local choices
        choices=$(dialog --stdout --backtitle "Post Install - AI Coding Agents Stack" \
            --title " AI Coding Agents Installer (TUI) " \
            --checklist "Select the terminal AI agents to install on your system:\n[UP/DOWN]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm" \
            16 78 4 \
            "claude"   "Claude Code (claude-code via AUR TUI agent)"       ON \
            "opencode" "OpenCode (Autonomous Terminal Coding Agent TUI)"   ON \
            "agy"      "Google Antigravity CLI (Agentic Companion TUI)"    ON \
            "ollama"   "Ollama (Local LLM Engine - AMD ROCm Accelerated)"  ON) || {
            clear 2>/dev/null || true
            log "Installation cancelled by user."
            exit 0
        }
        clear 2>/dev/null || true

        for c in $choices; do
            case "$c" in
                \"claude\"|claude) DO_CLAUDE=true ;;
                \"opencode\"|opencode) DO_OPENCODE=true ;;
                \"agy\"|agy) DO_AGY=true ;;
                \"ollama\"|ollama) DO_OLLAMA=true ;;
            esac
        done
        return 0
    elif command -v whiptail &>/dev/null && [ -t 0 ]; then
        local choices
        choices=$(whiptail --title " AI Coding Agents Installer (TUI) " \
            --checklist "Select the terminal AI agents to install on your system:\n[UP/DOWN]=Navigate  [SPACE]=Toggle  [ENTER]=Confirm" \
            16 78 4 \
            "claude"   "Claude Code (claude-code via AUR TUI)"       ON \
            "opencode" "OpenCode (Terminal Coding Agent TUI)"        ON \
            "agy"      "Google Antigravity CLI (Agentic Companion)"  ON \
            "ollama"   "Ollama (Local LLM Engine - AMD ROCm)"        ON \
            3>&1 1>&2 2>&3) || {
            clear 2>/dev/null || true
            log "Installation cancelled by user."
            exit 0
        }
        clear 2>/dev/null || true

        for c in $choices; do
            case "$c" in
                \"claude\"|claude) DO_CLAUDE=true ;;
                \"opencode\"|opencode) DO_OPENCODE=true ;;
                \"agy\"|agy) DO_AGY=true ;;
                \"ollama\"|ollama) DO_OLLAMA=true ;;
            esac
        done
        return 0
    fi

    # Fallback text-based menu if running non-interactively without dialog/whiptail
    echo -e "${CYAN}${BOLD}"
    cat <<'EOF'
    ___    ____   ______           ___                 __      
   /   |  /  _/  / ____/___  ____/ (_)___  ____ _     / /____  
  / /| |  / /   / /   / __ \/ __  / / __ \/ __ `/    / //_/ _ \ 
 / ___ |_/ /   / /___/ /_/ / /_/ / / / / / /_/ /    / ,< /  __/ 
/_/  |_/___/   \____/\____/\__,_/_/_/ /_/\__, /____/_/|_|\___/  
                                         /____/_____/           
EOF
    echo -e "${NC}"
    echo -e "${BOLD}AI Coding Agents Installer for Arch Linux (TUI)${NC}"
    echo -e "${BLUE}Terminal User Interface Mode${NC}"
    echo "--------------------------------------------------------"
    echo "  1) All TUI AI Agents (Claude Code, OpenCode, AGY, Ollama)"
    echo "  2) Claude Code (claude-code via AUR TUI)"
    echo "  3) OpenCode (open-source terminal coding assistant)"
    echo "  4) Google Antigravity CLI (agy TUI companion)"
    echo "  5) Ollama (local LLM runner with ROCm auto-detect)"
    echo "  6) Custom Selection (e.g. '2 3 5')"
    echo "  q) Quit"
    echo "--------------------------------------------------------"
    read -rp "Select an option [1-6, q]: " choice

    case "$choice" in
        1)
            DO_CLAUDE=true
            DO_OPENCODE=true
            DO_AGY=true
            DO_OLLAMA=true
            ;;
        2)
            DO_CLAUDE=true
            ;;
        3)
            DO_OPENCODE=true
            ;;
        4)
            DO_AGY=true
            ;;
        5)
            DO_OLLAMA=true
            ;;
        6)
            read -rp "Enter choice numbers separated by spaces (e.g. 2 4 5): " selections
            for s in $selections; do
                case "$s" in
                    2) DO_CLAUDE=true ;;
                    3) DO_OPENCODE=true ;;
                    4) DO_AGY=true ;;
                    5) DO_OLLAMA=true ;;
                    *) warn "Invalid selection ignored: $s" ;;
                esac
            done
            ;;
        q|Q)
            log "Installation cancelled by user."
            exit 0
            ;;
        *)
            err "Invalid option: $choice"
            exit 1
            ;;
    esac
}

# --- Post-install Summary Report ---
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD}                 AI AGENTS INSTALLATION SUMMARY                       ${NC}"
    echo -e "${GREEN}${BOLD}======================================================================${NC}"
    printf "%-26s %-16s %s\n" "TOOL" "STATUS" "VERSION / SERVICE"
    echo "----------------------------------------------------------------------"

    # Claude Code
    if command -v claude &>/dev/null; then
        printf "%-26s ${GREEN}%-16s${NC} %s\n" "Claude Code" "Installed" "$(claude --version 2>/dev/null || echo 'active')"
    else
        printf "%-26s ${YELLOW}%-16s${NC} %s\n" "Claude Code" "Not Installed" "-"
    fi

    # OpenCode
    if command -v opencode &>/dev/null; then
        printf "%-26s ${GREEN}%-16s${NC} %s\n" "OpenCode" "Installed" "$(opencode --version 2>/dev/null || echo 'active')"
    else
        printf "%-26s ${YELLOW}%-16s${NC} %s\n" "OpenCode" "Not Installed" "-"
    fi

    # Google Antigravity CLI
    if command -v agy &>/dev/null; then
        printf "%-26s ${GREEN}%-16s${NC} %s\n" "Antigravity CLI (agy)" "Installed" "$(agy --version 2>/dev/null || echo 'active')"
    else
        printf "%-26s ${YELLOW}%-16s${NC} %s\n" "Antigravity CLI (agy)" "Not Installed" "-"
    fi

    # Ollama
    if command -v ollama &>/dev/null; then
        local svc_status="systemd inactive"
        if systemctl is-active --quiet ollama.service 2>/dev/null; then
            svc_status="systemd active"
        fi
        printf "%-26s ${GREEN}%-16s${NC} %s (%s)\n" "Ollama" "Installed" "$(ollama --version 2>/dev/null || echo 'active')" "$svc_status"
    else
        printf "%-26s ${YELLOW}%-16s${NC} %s\n" "Ollama" "Not Installed" "-"
    fi

    echo "----------------------------------------------------------------------"
    echo -e "${CYAN}${BOLD}Quick Start Cheat-Sheet:${NC}"
    echo "  • Claude Code:   'claude'                (Sign in or set ANTHROPIC_API_KEY)"
    echo "  • OpenCode:      'opencode'              (Open source agentic CLI)"
    echo "  • Antigravity:   'agy'                   (Google Antigravity platform companion)"
    echo "  • Ollama:        'ollama run <model>'    (e.g., ollama run qwen2.5-coder:7b)"
    echo -e "${GREEN}All operations completed!${NC}"
}

# --- Main entry point (TUI-Only) ---
main() {
    check_user

    # Always present the interactive TUI checklist
    interactive_menu

    # If no agents were selected, exit cleanly
    if [ "$DO_CLAUDE" = false ] && [ "$DO_OPENCODE" = false ] && [ "$DO_AGY" = false ] && [ "$DO_OLLAMA" = false ]; then
        log "No AI agents selected. Exiting."
        exit 0
    fi

    # Check prerequisites before installing selected tools
    check_prerequisites

    # Execute selected installations
    if [ "$DO_CLAUDE" = true ]; then
        install_claude
    fi

    if [ "$DO_OPENCODE" = true ]; then
        install_opencode
    fi

    if [ "$DO_AGY" = true ]; then
        install_agy
    fi

    if [ "$DO_OLLAMA" = true ]; then
        install_ollama
    fi

    # Print final summary
    print_summary
}

main "$@"
