#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
LOADER_URL="https://codeberg.org/code07/test01/raw/branch/main/loader.jar"

# Fetch the latest version that has a JAR download from PortSwigger's release API
echo "Fetching latest Burp Suite version..."
BURP_VERSION="${BURP_VERSION:-$(curl -s 'https://portswigger.net/burp/releases/data?pageSize=10' \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['ResultSet']['Results']:
    if any(b['BuildCategoryPlatform'] == 'Jar' for b in r.get('builds', [])):
        print(r['version']); break
" 2>/dev/null)}"
if [ -z "$BURP_VERSION" ]; then
    echo "ERROR: Could not determine latest Burp Suite version. Check your internet connection."
    exit 1
fi
JAR_NAME="burpsuite_pro_v${BURP_VERSION}.jar"
DOWNLOAD_URL="https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VERSION&type=Jar"
echo "Latest version: $BURP_VERSION"

echo "=== Installing Burp Suite Professional (Arch Linux) ==="

# 1. Dependency installation (Pacman handles idempotency via --needed)
echo "Installing dependencies..."
if ! command -v java &>/dev/null || ! command -v wget &>/dev/null || ! command -v curl &>/dev/null; then
    sudo pacman -S --noconfirm --needed jdk21-openjdk wget curl

    echo "Setting Java 21 as default..."
    sudo archlinux-java set java-21-openjdk 2>/dev/null || sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk/bin/java 2>/dev/null || true
else
    echo "Dependencies already satisfied (java, wget, curl present)."
fi

# 2. Install directory preparation
mkdir -p "$REPO_DIR"

echo "Downloading loader.jar..."
curl -fL --progress-bar -o "$REPO_DIR/loader.jar" "$LOADER_URL"

# Helper function to compare version strings: returns 0 (true) if $1 >= $2
version_ge() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

cd "$REPO_DIR"

# 3. Check existing Burp Suite Pro JAR version
SKIP_DOWNLOAD=false
if compgen -G "$REPO_DIR/burpsuite_pro_v*.jar" >/dev/null; then
    EXISTING_JAR="$(ls -1 "$REPO_DIR"/burpsuite_pro_v*.jar 2>/dev/null | sort -V | tail -n1 || true)"
    if [ -n "$EXISTING_JAR" ] && [ -f "$EXISTING_JAR" ]; then
        EXISTING_VERSION="$(basename "$EXISTING_JAR" | sed -E 's/^burpsuite_pro_v(.*)\.jar$/\1/')"
        EXISTING_SIZE="$(stat -c%s "$EXISTING_JAR" 2>/dev/null || stat -f%z "$EXISTING_JAR" 2>/dev/null || echo 0)"
        if [ "$EXISTING_SIZE" -gt 10485760 ]; then
            if [ "$EXISTING_VERSION" = "$BURP_VERSION" ]; then
                echo "Burp Suite Professional $BURP_VERSION is already downloaded and up-to-date. Skipping download."
                SKIP_DOWNLOAD=true
                JAR_NAME="$(basename "$EXISTING_JAR")"
            elif version_ge "$EXISTING_VERSION" "$BURP_VERSION"; then
                echo "Installed version ($EXISTING_VERSION) is newer than PortSwigger release ($BURP_VERSION). Skipping download."
                SKIP_DOWNLOAD=true
                JAR_NAME="$(basename "$EXISTING_JAR")"
            else
                echo "Found older version ($EXISTING_VERSION). Upgrading to latest ($BURP_VERSION)..."
            fi
        else
            echo "Existing JAR file ($EXISTING_JAR) is incomplete or corrupted ($EXISTING_SIZE bytes). Re-downloading..."
        fi
    fi
fi

if [ "$SKIP_DOWNLOAD" = false ]; then
    echo "Downloading Burp Suite Professional $BURP_VERSION ($JAR_NAME)..."
    wget -O "$JAR_NAME.tmp" --quiet --show-progress "$DOWNLOAD_URL"
    mv "$JAR_NAME.tmp" "$JAR_NAME"

    # Remove older Burp JARs now that download succeeded
    find "$REPO_DIR" -maxdepth 1 -name 'burpsuite_pro_v*.jar' ! -name "$JAR_NAME" -delete 2>/dev/null || true
fi

# Calculate and display checksums
if [ -f "$JAR_NAME" ]; then
    echo "--- File Checksums ---"
    echo "SHA256: $(sha256sum "$JAR_NAME" | cut -d' ' -f1)"
    echo "MD5:    $(md5sum "$JAR_NAME" | cut -d' ' -f1)"
fi

# 4. Copy local config files if present
echo "Copying local assets..."
cp "$SCRIPT_DIR/.config.ini" "$REPO_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/burp_suite_pro_icon.svg" "$REPO_DIR/" 2>/dev/null || true

# 5. Create launcher binary script
mkdir -p "$HOME/.local/bin"
LAUNCHER_PATH="$HOME/.local/bin/burpsuitepro"

echo "Creating launcher script at $LAUNCHER_PATH..."
cat <<EOF >"$LAUNCHER_PATH"
#!/bin/bash
# Wayland and tiling WM compatibility
export _JAVA_AWT_WM_NONREPARENTING=1
if [ -z "\${DISPLAY:-}" ]; then
    if [ -n "\${WAYLAND_DISPLAY:-}" ] || [ -e /tmp/.X11-unix/X0 ]; then
        export DISPLAY=:0
    fi
fi
java --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:$REPO_DIR/loader.jar -noverify -jar $REPO_DIR/$JAR_NAME "\$@"
EOF
chmod +x "$LAUNCHER_PATH"

sudo -n ln -sf "$LAUNCHER_PATH" /usr/local/bin/burpsuitepro 2>/dev/null || true

# 6. Create Desktop Shortcut
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/burpsuitepro.desktop"

echo "Creating desktop entry at $DESKTOP_FILE..."
cat <<EOF >"$DESKTOP_FILE"
[Desktop Entry]
Name=Burp Suite Professional
Comment=Burp Suite Professional - Web Application Security Testing
Exec=$LAUNCHER_PATH
Icon=$REPO_DIR/burp_suite_pro_icon.svg
Terminal=false
Type=Application
Categories=Network;Security;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
StartupWMClass=burp-StartBurp
EOF

# 7. Start Key Loader & Burp Suite Pro
if [ -z "${DISPLAY:-}" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -e /tmp/.X11-unix/X0 ]; then
        export DISPLAY=:0
    fi
fi

if [ -f "$REPO_DIR/loader.jar" ]; then
    echo "Starting Key loader.jar in background..."
    nohup java -jar "$REPO_DIR/loader.jar" >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

echo "Starting Burp Suite Professional..."
nohup "$LAUNCHER_PATH" >/dev/null 2>&1 &
disown 2>/dev/null || true

echo "=== Burp Suite Professional (Arch Linux) installation completed successfully! ==="
