#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
LAUNCHER_PATH="$HOME/.local/bin/burpsuitepro"
DESKTOP_FILE="$HOME/.local/share/applications/burpsuitepro.desktop"

echo "=== Burp Suite Professional Full Uninstaller (Arch Linux) ==="

# 1. Stop running processes
echo "Stopping any running Burp Suite processes..."
pkill -f "burpsuite_pro|loader.jar|burpsuitepro" 2>/dev/null || true

# 2. Remove desktop shortcut & symlinks
echo "Removing desktop entry and binaries..."
rm -f "$DESKTOP_FILE"
rm -f "$LAUNCHER_PATH"
sudo -n rm -f /usr/local/bin/burpsuitepro 2>/dev/null || true

# 3. Remove installation directory
if [[ -d "$REPO_DIR" ]]; then
    echo "Removing installation folder: $REPO_DIR"
    rm -rf "$REPO_DIR"
fi

# Clean parent Crack folder if empty
PARENT_DIR="$(dirname "$REPO_DIR")"
if [[ -d "$PARENT_DIR" ]] && [[ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]]; then
    rmdir "$PARENT_DIR" 2>/dev/null || true
fi

# 4. Clean user preferences and caches (unless --keep-data passed)
if [[ "${1:-}" != "--keep-data" ]]; then
    echo "Cleaning user data and caches..."
    rm -rf "$HOME/.BurpSuite"
    rm -rf "$HOME/.java/.userPrefs/burp"
    rm -rf "$HOME/.java/.userPrefs/BurpSuite"
fi

# 5. Update desktop database
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "=== Burp Suite Professional has been completely removed from Arch Linux! ==="
