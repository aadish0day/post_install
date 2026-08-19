#!/usr/bin/env bash
# ============================================================================
# Post-Installation Automation Suite (Universal Launcher)
# Provides Archinstall-style interactive TUI with pure shell fallback.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If Python 3 is available, launch the Archinstall-style TUI interface
if command -v python3 &>/dev/null; then
    exec python3 "$SCRIPT_DIR/install.py" "$@"
fi

# ============================================================================
# FALLBACK: PURE SHELL EXECUTION (if python3 is not available)
# ============================================================================
echo "Python 3 not found. Falling back to native shell mode..."

detect_distro() {
	if [ -d "/data/data/com.termux" ] || [ -n "${TERMUX_VERSION:-}" ]; then
		echo "termux"
		return 0
	fi

	if [ -f /etc/os-release ]; then
		local ID="" ID_LIKE=""
		. /etc/os-release

		case "${ID:-}" in
		kali) echo "kali"; return 0 ;;
		arch | manjaro | endeavouros | garuda | artix | cachyos) echo "arch"; return 0 ;;
		fedora | rhel | centos | rocky | almalinux | nobara) echo "fedora"; return 0 ;;
		debian | ubuntu | pop | linuxmint | elementary | raspbian) echo "debian"; return 0 ;;
		esac

		for like in ${ID_LIKE:-}; do
			case "$like" in
			arch) echo "arch"; return 0 ;;
			fedora | rhel) echo "fedora"; return 0 ;;
			debian | ubuntu) echo "debian"; return 0 ;;
			esac
		done
	fi

	echo "unknown"
	return 1
}

DETECTED_DISTRO=$(detect_distro || echo "unknown")

case "$DETECTED_DISTRO" in
debian) echo "Auto-detected OS: Debian/Ubuntu"; DISTRO_DIR="debian" ;;
arch)   echo "Auto-detected OS: Arch Linux";    DISTRO_DIR="arch" ;;
fedora) echo "Auto-detected OS: Fedora";        DISTRO_DIR="fedora" ;;
kali)   echo "Auto-detected OS: Kali Linux";    DISTRO_DIR="kali" ;;
termux) echo "Auto-detected OS: Termux";        DISTRO_DIR="termux" ;;
*)
	echo "Could not auto-detect distribution."
	echo "1) Debian/Ubuntu 2) Arch Linux 3) Fedora 4) Kali Linux 5) Termux"
	read -rp "Distribution (1-5): " CHOICE
	case "$CHOICE" in
	1) DISTRO_DIR="debian" ;;
	2) DISTRO_DIR="arch" ;;
	3) DISTRO_DIR="fedora" ;;
	4) DISTRO_DIR="kali" ;;
	5) DISTRO_DIR="termux" ;;
	*) echo "Invalid selection."; exit 1 ;;
	esac
	;;
esac

# Clone Neovim configuration if missing
NVIM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ ! -d "$NVIM_DIR" ]; then
	echo "Cloning Neovim configuration..."
	git clone https://github.com/Aadishx07/neovim_config.git "$NVIM_DIR" || { echo "Failed to clone nvim config."; exit 1; }
fi

mkdir -p "$HOME/Pictures/Screenshots"

SCRIPT="$SCRIPT_DIR/$DISTRO_DIR/$DISTRO_DIR.sh"
if [ -f "$SCRIPT" ]; then
	(cd "$SCRIPT_DIR/$DISTRO_DIR" && ./"$DISTRO_DIR.sh") || { echo "Installation script failed for $DISTRO_DIR."; exit 1; }
else
	echo "Script $SCRIPT not found."
	exit 1
fi

echo "Setup completed successfully!"
