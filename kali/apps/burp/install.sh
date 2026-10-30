#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
BURP_STABLE_VERSION="2026.10.1"

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS] [VERSION]

Install Burp Suite Professional with a selectable version channel.

Options:
  -v, --version <ver>   Install an exact version (e.g. 2026.10.1)
      --channel <name>  Version channel: stable (tested) or latest (UNTESTED)
  -f, --force           Re-download even if files already exist
      --skip-launch     Install without launching Burp Suite
  -h, --help            Show this help and exit

Environment:
  BURP_VERSION          Same as --version; -v takes precedence

With no --version, --channel, or BURP_VERSION, the installer prompts for
stable or latest when stdin and stdout are a terminal. Otherwise it
defaults to the tested stable version.
EOF
}

# Parse CLI options
SKIP_LAUNCH=false
FORCE_DOWNLOAD=false
CUSTOM_VERSION=""
CHANNEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: $1 requires a version argument." >&2
                exit 1
            fi
            CUSTOM_VERSION="$2"
            shift 2
            ;;
        --skip-launch)
            SKIP_LAUNCH=true
            shift
            ;;
        -f|--force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --channel)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: $1 requires a channel argument (stable or latest)." >&2
                exit 1
            fi
            CHANNEL="$2"
            shift 2
            ;;
        *)
            if [[ -z "$CUSTOM_VERSION" && "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                CUSTOM_VERSION="$1"
            fi
            shift
            ;;
    esac
done

# Interactive channel picker (only used on a TTY when nothing was specified)
prompt_channel() {
    local reply=""
    echo ""
    echo "Burp Suite Professional - version channel"
    echo "  1) Tested stable  v$BURP_STABLE_VERSION  (recommended)"
    echo "  2) Latest         newest PortSwigger release (UNTESTED)"
    while true; do
        printf 'Select [1]: '
        if ! IFS= read -r reply; then
            # EOF or read failure: fall back to the tested stable channel.
            reply=1
        fi
        case "${reply,,}" in
            ""|1|stable|s)
                CHANNEL="stable"
                break
                ;;
            2|latest|l)
                CHANNEL="latest"
                break
                ;;
            *)
                echo "Invalid selection '$reply'. Enter 1 for tested stable or 2 for latest (UNTESTED)."
                ;;
        esac
    done
    echo ""
}

# Resolve version (CLI -v -> BURP_VERSION env -> --channel -> prompt -> stable fallback)
IS_CUSTOM=false
if [[ -n "$CUSTOM_VERSION" ]]; then
    BURP_VERSION="$CUSTOM_VERSION"
    IS_CUSTOM=true
    echo "Using specified Burp Suite version: $BURP_VERSION"
elif [[ -n "${BURP_VERSION:-}" ]]; then
    IS_CUSTOM=true
    echo "Using environment BURP_VERSION: $BURP_VERSION"
else
    if [[ -z "$CHANNEL" ]]; then
        if [[ -t 0 && -t 1 ]]; then
            prompt_channel
        else
            CHANNEL="stable"
            echo "No version or channel specified; defaulting to tested stable version v$BURP_STABLE_VERSION."
        fi
    fi

    CHANNEL="${CHANNEL,,}"
    if [[ "$CHANNEL" == "stable" ]]; then
        BURP_VERSION="$BURP_STABLE_VERSION"
        echo "Using stable (tested) Burp Suite version: $BURP_VERSION"
    elif [[ "$CHANNEL" == "latest" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  ⚠  WARNING: Latest channel selected (UNTESTED)            ║"
        echo "║  This fetches the newest release from PortSwigger.          ║"
        echo "║  It may contain breaking changes or compatibility issues.   ║"
        echo "║  Use 'stable' channel for a known-good version.            ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Fetching latest Burp Suite version from PortSwigger..."
        BURP_VERSION="$(curl -sSL --connect-timeout 10 --max-time 15 'https://portswigger.net/burp/releases/data?pageSize=10' 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        for r in data.get('ResultSet', {}).get('Results', []):
            if any(b.get('BuildCategoryPlatform') == 'Jar' for b in r.get('builds', [])):
                v = r.get('version')
                if v:
                    print(v)
                    sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)"

        if [[ -z "$BURP_VERSION" ]]; then
            echo "PortSwigger API unavailable or rate-limited, checking GitHub release..."
            BURP_VERSION="$(curl -sSL --connect-timeout 10 --max-time 15 'https://api.github.com/repos/xiv3r/Burpsuite-Professional/releases/latest' 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        tag = data.get('tag_name')
        if tag:
            print(tag.lstrip('v'))
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)"
        fi

        if [[ -z "$BURP_VERSION" ]]; then
            BURP_VERSION="$BURP_STABLE_VERSION"
            echo "All APIs unavailable. Falling back to stable version: $BURP_VERSION"
        else
            echo "Latest version detected: $BURP_VERSION"
        fi
    else
        echo "ERROR: Invalid channel '$CHANNEL'. Use 'stable' or 'latest'."
        exit 1
    fi
fi

JAR_NAME="burpsuite_pro_v${BURP_VERSION}.jar"
DOWNLOAD_URL="https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VERSION&type=Jar"

echo "=== Installing Burp Suite Professional ==="

# 1. Dependency installation
echo "Installing dependencies..."
if ! command -v java &>/dev/null || ! command -v wget &>/dev/null || ! command -v curl &>/dev/null; then
    if command -v nala &>/dev/null; then
        sudo nala install -y openjdk-21-jre wget curl
    else
        sudo apt update -qq && sudo apt install -y openjdk-21-jre wget curl
    fi

    echo "Setting Java 21 as default..."
    sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 2>/dev/null || true
else
    echo "Dependencies already satisfied (java, wget, curl present)."
fi

# 2. Install directory preparation
mkdir -p "$REPO_DIR"

LOADER_URLS=(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
    "https://raw.githubusercontent.com/xiv3r/Burpsuite-Professional/main/loader.jar"
)

LOADER_FILE="$REPO_DIR/loader.jar"
if [[ -f "$LOADER_FILE" && $(stat -c%s "$LOADER_FILE" 2>/dev/null || echo 0) -gt 10240 && "$FORCE_DOWNLOAD" == false ]]; then
    echo "Existing loader.jar verified. Skipping download."
else
    echo "Downloading loader.jar..."
    LOADER_DOWNLOADED=false
    for url in "${LOADER_URLS[@]}"; do
        echo "Attempting loader download from: $url"
        if curl -fL --connect-timeout 10 --max-time 60 --progress-bar -o "$LOADER_FILE" "$url" 2>/dev/null; then
            if [[ $(stat -c%s "$LOADER_FILE" 2>/dev/null || echo 0) -gt 10240 ]]; then
                echo "Successfully downloaded loader.jar"
                LOADER_DOWNLOADED=true
                break
            else
                echo "Downloaded loader.jar from $url is invalid or too small, trying next mirror..."
                rm -f "$LOADER_FILE"
            fi
        else
            echo "Failed to download from $url, trying fallback mirror..."
        fi
    done
    if [[ "$LOADER_DOWNLOADED" == false ]]; then
        echo "ERROR: Failed to download loader.jar from all mirrors. Check your internet connection."
        exit 1
    fi
fi

# Helper function to compare version strings: returns 0 (true) if $1 >= $2
version_ge() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

cd "$REPO_DIR"

# 3. Check existing Burp Suite Pro JAR version
SKIP_DOWNLOAD=false
if [[ "$FORCE_DOWNLOAD" == false ]] && compgen -G "$REPO_DIR/burpsuite_pro_v*.jar" >/dev/null; then
    if [ "$IS_CUSTOM" = true ]; then
        if [ -f "$REPO_DIR/$JAR_NAME" ] && [ "$(stat -c%s "$REPO_DIR/$JAR_NAME" 2>/dev/null || echo 0)" -gt 10485760 ]; then
            echo "Requested version $BURP_VERSION is already downloaded. Skipping download."
            SKIP_DOWNLOAD=true
        fi
    else
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
if [ "$SKIP_LAUNCH" = true ]; then
    echo "Skipping Burp Suite Pro launch (--skip-launch specified)."
else
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
fi

echo "=== Burp Suite Professional installation completed successfully! ==="
