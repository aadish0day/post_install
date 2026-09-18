#!/usr/bin/env bash
# ============================================================================
# Post-Installation Automation Suite (Universal Launcher)
# Provides Archinstall-style interactive TUI with pure shell fallback.
# Every run mirrors the full session (stdout + stderr) to a log in /tmp:
#   /tmp/post-install-YYYYmmdd_HHMMSS.log
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# LOGGING: mirror the full session (stdout + stderr) into /tmp.
# Uses `script` when available so the interactive TUI keeps working, with a
# `tee` fallback for systems lacking `script` (there the TUI degrades to CLI).
# Re-invocation is guarded by POST_INSTALL_LOGGED to avoid infinite recursion;
# the inner run reuses the same LOG_FILE via POST_INSTALL_LOG_FILE.
# ============================================================================
if [ -n "${POST_INSTALL_LOGGED:-}" ] && [ -n "${POST_INSTALL_LOG_FILE:-}" ]; then
	LOG_FILE="$POST_INSTALL_LOG_FILE"
else
	LOG_FILE="/tmp/post-install-$(date +%Y%m%d_%H%M%S).log"
fi

if [ -z "${POST_INSTALL_LOGGED:-}" ]; then
	export POST_INSTALL_LOGGED=1 POST_INSTALL_LOG_FILE="$LOG_FILE"
	if command -v script &>/dev/null; then
		# Remember whether we were attached to a real terminal before the
		# pty re-invocation, so the TUI decision below is unchanged.
		ORIG_TTY=no
		[ -t 0 ] && [ -t 1 ] && ORIG_TTY=yes
		export POST_INSTALL_ORIG_TTY="$ORIG_TTY"
		printf '==> Full session log: %s\n' "$LOG_FILE"
		# Re-invoke via absolute path: "$0" may be relative (e.g. `bash
		# install.sh`), which script's inner shell cannot resolve alone.
		printf -v SELF_Q '%q' "$SCRIPT_DIR/$(basename "$0")"
		printf -v BASH_Q '%q' "$BASH"
		ARGS=""
		for a in "$@"; do
			printf -v aq '%q' "$a"
			ARGS+=" $aq"
		done
		exec script -qefc "$BASH_Q $SELF_Q$ARGS" "$LOG_FILE"
	fi
	# `script` missing: fall back to tee (still captures everything).
	export PYTHONUNBUFFERED=1
	exec > >(tee "$LOG_FILE") 2>&1
	trap 'wait' EXIT
fi

# Fixed-name symlink for easy access + session header (both captured in log).
ln -sf "$LOG_FILE" /tmp/post-install-latest.log || true
printf '==> Session start: %s | args: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${*:-none}"
printf '==> Full log: %s\n' "$LOG_FILE"

# Install Textual (the archinstall-style interface) if it's missing or too old.
# Failures are non-fatal: install.py falls back to the curses interface.
ensure_textual() {
	python3 -c 'import sys, importlib.metadata as m; sys.exit(int(m.version("textual").split(".")[0]) < 2)' &>/dev/null && return 0

	echo "Installing Textual for the archinstall-style interface..."
	if [ -d "/data/data/com.termux" ] || [ -n "${TERMUX_VERSION:-}" ]; then
		pip install --quiet textual
	elif command -v pacman &>/dev/null; then
		sudo pacman -S --needed --noconfirm python-textual
	elif command -v apt-get &>/dev/null; then
		sudo apt-get install -y python3-textual
	elif command -v dnf &>/dev/null; then
		sudo dnf install -y python3-textual
	else
		python3 -m pip install --user --quiet textual
	fi || echo "Could not install Textual; using the classic curses interface."
}

# If Python 3 is available, launch the Archinstall-style TUI interface
if command -v python3 &>/dev/null; then
	needs_tui=true
	if [ "${POST_INSTALL_ORIG_TTY:-auto}" = auto ]; then
		[ -t 0 ] && [ -t 1 ] || needs_tui=false
	else
		[ "$POST_INSTALL_ORIG_TTY" = yes ] || needs_tui=false
	fi
	for arg in "$@"; do
		case "$arg" in
		--headless | --cli | --save-config* | curses | --tui=curses) needs_tui=false ;;
		esac
	done
	[ "$needs_tui" = true ] && ensure_textual

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
