#!/usr/bin/env bash
# ============================================================================
# Burp Suite Professional Universal Uninstaller
# ============================================================================

set -euo pipefail

REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
LAUNCHER_PATH="$HOME/.local/bin/burpsuitepro"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/burpsuitepro.desktop"
KEYGEN_DESKTOP_FILE="$DESKTOP_DIR/burpsuitepro-keygen.desktop"

echo "=== Burp Suite Professional Full Uninstaller ==="

# 1. Stop running processes
echo "Stopping any running Burp Suite processes..."
pkill -f "burpsuite_pro|loader.jar|burpsuitepro" 2>/dev/null || true

# 2. Remove desktop shortcuts, icons, MIME definitions & binaries
echo "Removing desktop entries, icons, MIME definitions, and binaries..."
rm -f "$DESKTOP_FILE"
rm -f "$KEYGEN_DESKTOP_FILE"
rm -f "$LAUNCHER_PATH"

# Remove user-level icons
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/burpsuitepro.svg"
for icon in "$HOME/.local/share/icons/hicolor"/*/apps/burpsuitepro.png; do
    if [ -f "$icon" ]; then
        rm -f "$icon"
    fi
done
rm -f "$HOME/.local/share/pixmaps/burpsuitepro.svg"
rm -f "$HOME/.local/share/pixmaps/burpsuitepro.png"

# Remove user-level MIME definition
rm -f "$HOME/.local/share/mime/packages/burpsuitepro.xml"

# Attempt cleanup in system paths if writable or passwordless sudo
if [[ -w /usr/local/bin ]]; then
    rm -f /usr/local/bin/burpsuitepro 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n rm -f /usr/local/bin/burpsuitepro 2>/dev/null || true
fi

if [[ -w /usr/local/share/applications ]]; then
    rm -f /usr/local/share/applications/burpsuitepro.desktop /usr/local/share/applications/burpsuitepro-keygen.desktop 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n rm -f /usr/local/share/applications/burpsuitepro.desktop /usr/local/share/applications/burpsuitepro-keygen.desktop 2>/dev/null || true
fi

if [[ -w /usr/local/share/icons/hicolor ]]; then
    rm -f /usr/local/share/icons/hicolor/scalable/apps/burpsuitepro.svg 2>/dev/null || true
    for icon in /usr/local/share/icons/hicolor/*/apps/burpsuitepro.png; do
        if [ -f "$icon" ]; then
            rm -f "$icon" 2>/dev/null || true
        fi
    done
elif command -v sudo &>/dev/null; then
    sudo -n rm -f /usr/local/share/icons/hicolor/scalable/apps/burpsuitepro.svg 2>/dev/null || true
    sudo -n sh -c 'rm -f /usr/local/share/icons/hicolor/*/apps/burpsuitepro.png 2>/dev/null || true' 2>/dev/null || true
fi

if [[ -w /usr/share/pixmaps ]]; then
    rm -f /usr/share/pixmaps/burpsuitepro.svg /usr/share/pixmaps/burpsuitepro.png 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n rm -f /usr/share/pixmaps/burpsuitepro.svg /usr/share/pixmaps/burpsuitepro.png 2>/dev/null || true
fi

if [[ -w /usr/local/share/mime/packages ]]; then
    rm -f /usr/local/share/mime/packages/burpsuitepro.xml 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n rm -f /usr/local/share/mime/packages/burpsuitepro.xml 2>/dev/null || true
fi

# 3. Remove installation directory (includes loader.jar, Jython and JRuby standalone JARs)
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

# 5. Regenerate desktop, icon, and MIME caches
echo "Regenerating desktop, icon, and MIME caches..."
gtk-update-icon-cache -f -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
kbuildsycoca6 --noincremental 2>/dev/null || kbuildsycoca6 2>/dev/null || kbuildsycoca5 2>/dev/null || true

# System cache updates if writable or passwordless sudo
if [[ -w /usr/local/share/applications ]]; then
    update-desktop-database /usr/local/share/applications 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n update-desktop-database /usr/local/share/applications 2>/dev/null || true
fi

if [[ -w /usr/local/share/icons/hicolor ]]; then
    gtk-update-icon-cache -f -q -t /usr/local/share/icons/hicolor 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n gtk-update-icon-cache -f -q -t /usr/local/share/icons/hicolor 2>/dev/null || true
fi

if [[ -w /usr/local/share/mime ]]; then
    update-mime-database /usr/local/share/mime 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n update-mime-database /usr/local/share/mime 2>/dev/null || true
fi

echo "=== Burp Suite Professional has been completely removed! ==="
