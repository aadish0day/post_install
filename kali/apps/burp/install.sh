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
    -h | --help)
        usage
        exit 0
        ;;
    -v | --version)
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
    -f | --force)
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
        "" | 1 | stable | s)
            CHANNEL="stable"
            break
            ;;
        2 | latest | l)
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
if [[ -n "$CUSTOM_VERSION" ]]; then
    BURP_VERSION="$CUSTOM_VERSION"
    echo "Using specified Burp Suite version: $BURP_VERSION"
elif [[ -n "${BURP_VERSION:-}" ]]; then
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

# 1. Running Process Detection
if pgrep -f 'burpsuite_pro_v.*\.jar' >/dev/null 2>&1; then
    echo "[!] Warning: Burp Suite Professional is currently running."
    echo "Please close Burp Suite before upgrading to avoid file lock issues."
    if [ -t 0 ]; then
        read -rp "Press Enter once Burp Suite is closed, or Ctrl+C to cancel..." || true
    fi
fi

echo "=== Installing Burp Suite Professional ==="

# 2. Dependency installation
echo "Installing dependencies..."
if ! command -v java &>/dev/null || ! command -v wget &>/dev/null || ! command -v curl &>/dev/null || ! command -v certutil &>/dev/null; then
    if command -v nala &>/dev/null; then
        sudo nala install -y openjdk-21-jre wget curl libnss3-tools
    else
        sudo apt update -qq && sudo apt install -y openjdk-21-jre wget curl libnss3-tools
    fi

    echo "Setting Java 21 as default..."
    sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 2>/dev/null || true
else
    echo "Dependencies already satisfied (java, wget, curl present)."
fi

# Embedded Chromium sandbox fix (unprivileged user namespaces for Kali/Debian)
if [[ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || true)" == "0" ]]; then
    echo "Enabling unprivileged user namespaces for embedded Chromium sandbox..."
    if command -v sudo &>/dev/null; then
        sudo sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
        echo "kernel.unprivileged_userns_clone=1" | sudo tee /etc/sysctl.d/99-burp-userns.conf >/dev/null 2>&1 || true
    elif [[ $EUID -eq 0 ]]; then
        sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
        echo "kernel.unprivileged_userns_clone=1" >/etc/sysctl.d/99-burp-userns.conf 2>/dev/null || true
    fi
fi

# Helper function to get file size in bytes
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# Helper function to compare version strings: returns 0 (true) if $1 >= $2
version_ge() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Pre-seed JRE warning suppression
suppress_jre_warnings() {
    local prefs_dir="$HOME/.java/.userPrefs/burp"
    local prefs_file="$prefs_dir/prefs.xml"
    mkdir -p "$prefs_dir"

    local keys=(
        "suite.alertsdisabledforjre-3189538875"
        "suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-3189538875"
        "burp.suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-1872878544"
        "burp.suite.alertsdisabledforjre-413592390"
    )

    if [[ ! -s "$prefs_file" ]]; then
        cat <<'EOF' >"$prefs_file"
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="suite.alertsdisabledforjre-3189538875" value="true"/>
  <entry key="suite.alertsdisabledforjre-1115054815" value="true"/>
  <entry key="burp.suite.alertsdisabledforjre-3189538875" value="true"/>
  <entry key="burp.suite.alertsdisabledforjre-1115054815" value="true"/>
  <entry key="burp.suite.alertsdisabledforjre-1872878544" value="true"/>
  <entry key="burp.suite.alertsdisabledforjre-413592390" value="true"/>
</map>
EOF
    else
        for key in "${keys[@]}"; do
            if ! grep -qF "key=\"$key\"" "$prefs_file"; then
                if grep -qF "</map>" "$prefs_file"; then
                    sed -i "/<\/map>/i \  <entry key=\"$key\" value=\"true\"/>" "$prefs_file"
                else
                    echo "  <entry key=\"$key\" value=\"true\"/>" >>"$prefs_file"
                fi
            fi
        done
    fi
}

# 2. Install directory preparation
mkdir -p "$REPO_DIR"

LOADER_URLS=(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
    "https://raw.githubusercontent.com/xiv3r/Burpsuite-Professional/main/loader.jar"
)

LOADER_FILE="$REPO_DIR/loader.jar"
if [[ -f "$LOADER_FILE" && $(get_file_size "$LOADER_FILE") -gt 10240 && "$FORCE_DOWNLOAD" == false ]]; then
    echo "Existing loader.jar verified (> 10KB). Skipping download."
else
    echo "Downloading loader.jar..."
    LOADER_DOWNLOADED=false
    for url in "${LOADER_URLS[@]}"; do
        echo "Attempting loader download from: $url"
        if curl -fL --connect-timeout 10 --max-time 60 --progress-bar -o "$LOADER_FILE.tmp" "$url" 2>/dev/null; then
            if [[ $(get_file_size "$LOADER_FILE.tmp") -gt 10240 ]]; then
                mv "$LOADER_FILE.tmp" "$LOADER_FILE"
                echo "Successfully downloaded loader.jar"
                LOADER_DOWNLOADED=true
                break
            else
                echo "Downloaded loader.jar from $url is invalid or too small, trying next mirror..."
                rm -f "$LOADER_FILE.tmp"
            fi
        else
            echo "Failed to download from $url, trying fallback mirror..."
        fi
    done
    if [[ "$LOADER_DOWNLOADED" == false ]]; then
        if [[ -f "$LOADER_FILE" && $(get_file_size "$LOADER_FILE") -gt 10240 ]]; then
            echo "WARNING: Failed to re-download loader.jar, but existing loader.jar is valid (> 10KB). Preserving existing file."
        else
            echo "ERROR: Failed to download loader.jar from all mirrors. Check your internet connection."
            exit 1
        fi
    fi
fi

cd "$REPO_DIR"

# 3. Check existing Burp Suite Pro JAR version
SKIP_DOWNLOAD=false
MIN_JAR_SIZE=10485760 # 10MB

if [[ "$FORCE_DOWNLOAD" == false ]]; then
    # Exact requested version already exists and is valid (> 10MB)
    if [[ -f "$REPO_DIR/$JAR_NAME" && $(get_file_size "$REPO_DIR/$JAR_NAME") -gt $MIN_JAR_SIZE ]]; then
        echo "Burp Suite Professional $BURP_VERSION is already present and verified ($JAR_NAME). Skipping download."
        SKIP_DOWNLOAD=true
    # Check if another existing JAR in $REPO_DIR has version >= requested version
    elif compgen -G "$REPO_DIR/burpsuite_pro_v*.jar" >/dev/null; then
        LATEST_VALID_JAR=""
        LATEST_VALID_VER=""
        while IFS= read -r candidate; do
            [[ -z "$candidate" || ! -f "$candidate" ]] && continue
            cand_size="$(get_file_size "$candidate")"
            if [[ "$cand_size" -gt $MIN_JAR_SIZE ]]; then
                LATEST_VALID_JAR="$candidate"
                LATEST_VALID_VER="$(basename "$candidate" | sed -E 's/^burpsuite_pro_v(.*)\.jar$/\1/')"
            else
                echo "Notice: Existing file $(basename "$candidate") is incomplete or corrupted ($cand_size bytes)."
            fi
        done < <(find "$REPO_DIR" -maxdepth 1 -name 'burpsuite_pro_v*.jar' 2>/dev/null | sort -V)

        if [[ -n "$LATEST_VALID_JAR" ]]; then
            if [[ "$LATEST_VALID_VER" == "$BURP_VERSION" ]]; then
                echo "Burp Suite Professional $BURP_VERSION is already present ($LATEST_VALID_JAR). Skipping download."
                SKIP_DOWNLOAD=true
                JAR_NAME="$(basename "$LATEST_VALID_JAR")"
            elif version_ge "$LATEST_VALID_VER" "$BURP_VERSION"; then
                echo "Installed Burp Suite version ($LATEST_VALID_VER) is >= requested version ($BURP_VERSION). Skipping download."
                SKIP_DOWNLOAD=true
                JAR_NAME="$(basename "$LATEST_VALID_JAR")"
            else
                echo "Found older version ($LATEST_VALID_VER). Upgrading to $BURP_VERSION..."
            fi
        fi
    fi
fi

if [[ "$SKIP_DOWNLOAD" == false ]]; then
    echo "Downloading Burp Suite Professional $BURP_VERSION ($JAR_NAME)..."
    JAR_DOWNLOADED=false
    if command -v aria2c &>/dev/null; then
        echo "Using aria2c accelerator (16 parallel connections)..."
        if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$JAR_NAME.tmp" "$DOWNLOAD_URL"; then
            if [[ -f "$JAR_NAME.tmp" && $(get_file_size "$JAR_NAME.tmp") -gt $MIN_JAR_SIZE ]]; then
                JAR_DOWNLOADED=true
            fi
        fi
        rm -f "$REPO_DIR/$JAR_NAME.tmp.aria2" 2>/dev/null || true
    fi
    if [[ "$JAR_DOWNLOADED" == false ]] && command -v curl &>/dev/null; then
        echo "Using curl with auto-resume..."
        if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$JAR_NAME.tmp" "$DOWNLOAD_URL"; then
            if [[ -f "$JAR_NAME.tmp" && $(get_file_size "$JAR_NAME.tmp") -gt $MIN_JAR_SIZE ]]; then
                JAR_DOWNLOADED=true
            fi
        fi
    fi
    if [[ "$JAR_DOWNLOADED" == false ]] && command -v wget &>/dev/null; then
        echo "Using wget with progress..."
        if wget -O "$JAR_NAME.tmp" --quiet --show-progress "$DOWNLOAD_URL"; then
            if [[ -f "$JAR_NAME.tmp" && $(get_file_size "$JAR_NAME.tmp") -gt $MIN_JAR_SIZE ]]; then
                JAR_DOWNLOADED=true
            fi
        fi
    fi

    if [[ "$JAR_DOWNLOADED" == false || ! -f "$JAR_NAME.tmp" || $(get_file_size "$JAR_NAME.tmp") -le $MIN_JAR_SIZE ]]; then
        echo "ERROR: Failed to download a valid Burp Suite JAR file (size <= 10MB or download failed)." >&2
        rm -f "$JAR_NAME.tmp" "$REPO_DIR/$JAR_NAME.tmp.aria2" 2>/dev/null || true
        exit 1
    fi

    mv -f "$JAR_NAME.tmp" "$JAR_NAME"

    # Backup older Burp JARs with .bk extension now that download succeeded
    for old_jar in "$REPO_DIR"/burpsuite_pro_v*.jar; do
        if [[ -f "$old_jar" && "$(basename "$old_jar")" != "$JAR_NAME" ]]; then
            echo "Backing up older version: $(basename "$old_jar") -> $(basename "$old_jar").bk"
            mv -f "$old_jar" "${old_jar}.bk"
        fi
    done
fi

# Calculate and display checksums
if [ -f "$JAR_NAME" ]; then
    echo "--- File Checksums ---"
    echo "SHA256: $(sha256sum "$JAR_NAME" | cut -d' ' -f1)"
    echo "MD5:    $(md5sum "$JAR_NAME" | cut -d' ' -f1)"
fi

# 4. Copy local config files & suppress JRE warnings
echo "Suppressing JRE warning dialogs..."
suppress_jre_warnings

echo "Copying local assets..."
if [[ ! -f "$REPO_DIR/.config.ini" && -f "$SCRIPT_DIR/.config.ini" ]]; then
    cp "$SCRIPT_DIR/.config.ini" "$REPO_DIR/" 2>/dev/null || true
fi
if [[ -f "$SCRIPT_DIR/burp_suite_pro_icon.svg" ]]; then
    cp "$SCRIPT_DIR/burp_suite_pro_icon.svg" "$REPO_DIR/" 2>/dev/null || true
fi

# 5. Built-in Jython Standalone 2.7.4 support
JYTHON_JAR="$REPO_DIR/jython-standalone-2.7.4.jar"
JYTHON_URL="https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"
MIN_JYTHON_SIZE=20971520 # 20MB

if [[ -f "$JYTHON_JAR" && $(get_file_size "$JYTHON_JAR") -gt $MIN_JYTHON_SIZE && "$FORCE_DOWNLOAD" == false ]]; then
    echo "Existing jython-standalone-2.7.4.jar verified (> 20MB). Skipping download."
else
    echo "Downloading Jython Standalone 2.7.4..."
    JYTHON_DOWNLOADED=false
    if command -v aria2c &>/dev/null; then
        echo "Using aria2c accelerator..."
        if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "jython-standalone-2.7.4.jar.tmp" "$JYTHON_URL" 2>/dev/null; then
            if [[ -f "$JYTHON_JAR.tmp" && $(get_file_size "$JYTHON_JAR.tmp") -gt $MIN_JYTHON_SIZE ]]; then
                JYTHON_DOWNLOADED=true
            fi
        fi
        rm -f "$REPO_DIR/jython-standalone-2.7.4.jar.tmp.aria2" 2>/dev/null || true
    fi
    if [[ "$JYTHON_DOWNLOADED" == false ]] && command -v curl &>/dev/null; then
        echo "Using curl with auto-resume..."
        if curl -fLC - --connect-timeout 10 --max-time 300 --progress-bar -o "$JYTHON_JAR.tmp" "$JYTHON_URL" 2>/dev/null; then
            if [[ -f "$JYTHON_JAR.tmp" && $(get_file_size "$JYTHON_JAR.tmp") -gt $MIN_JYTHON_SIZE ]]; then
                JYTHON_DOWNLOADED=true
            fi
        fi
    fi
    if [[ "$JYTHON_DOWNLOADED" == false ]] && command -v wget &>/dev/null; then
        echo "Using wget fallback..."
        if wget -O "$JYTHON_JAR.tmp" --quiet --show-progress "$JYTHON_URL"; then
            if [[ -f "$JYTHON_JAR.tmp" && $(get_file_size "$JYTHON_JAR.tmp") -gt $MIN_JYTHON_SIZE ]]; then
                JYTHON_DOWNLOADED=true
            fi
        fi
    fi

    if [[ "$JYTHON_DOWNLOADED" == true && -f "$JYTHON_JAR.tmp" && $(get_file_size "$JYTHON_JAR.tmp") -gt $MIN_JYTHON_SIZE ]]; then
        mv -f "$JYTHON_JAR.tmp" "$JYTHON_JAR"
        echo "Successfully downloaded jython-standalone-2.7.4.jar"
    else
        rm -f "$JYTHON_JAR.tmp" "$REPO_DIR/jython-standalone-2.7.4.jar.tmp.aria2" 2>/dev/null || true
        if [[ -f "$JYTHON_JAR" && $(get_file_size "$JYTHON_JAR") -gt $MIN_JYTHON_SIZE ]]; then
            echo "WARNING: Failed to re-download jython-standalone-2.7.4.jar, preserving existing valid file."
        else
            echo "WARNING: Failed to download valid jython-standalone-2.7.4.jar (size <= 20MB or network error)."
        fi
    fi
fi

# Configure Burp Suite User Config for Jython Extender
if [[ -f "$JYTHON_JAR" && $(get_file_size "$JYTHON_JAR") -gt $MIN_JYTHON_SIZE ]]; then
    echo "Configuring Burp Suite Jython path for Python BApps..."
    python3 - "$JYTHON_JAR" <<'PYEOF'
import json
import os
import sys

jython_path = sys.argv[1]
config_dir = os.path.expanduser("~/.BurpSuite")
os.makedirs(config_dir, exist_ok=True)

for config_filename in ("UserConfigPro.json", "UserConfig.json"):
    config_file = os.path.join(config_dir, config_filename)
    data = {}
    if os.path.isfile(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}
    if not isinstance(data, dict):
        data = {}

    user_options = data.setdefault("user_options", {})
    if not isinstance(user_options, dict):
        user_options = {}
        data["user_options"] = user_options

    extender = user_options.setdefault("extender", {})
    if not isinstance(extender, dict):
        extender = {}
        user_options["extender"] = extender

    python_opts = extender.setdefault("python", {})
    if not isinstance(python_opts, dict):
        python_opts = {}
        extender["python"] = python_opts

    python_opts["location_of_jython_standalone_jar_file"] = jython_path

    try:
        old_mode = os.stat(config_file).st_mode & 0o777
    except OSError:
        old_mode = 0o600

    tmp_file = config_file + ".tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.chmod(tmp_file, old_mode)
    os.replace(tmp_file, config_file)
PYEOF
    echo "Jython 2.7.4 configured in Burp Suite User Config."
fi

# 6. Create launcher binary script
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

REPO_DIR="$REPO_DIR"
JAR_NAME="$JAR_NAME"
BURP_VERSION="$BURP_VERSION"
EOF

cat <<'EOF' >>"$LAUNCHER_PATH"

# Dedicated CLI helper flags
case "${1:-}" in
    --keygen|-k)
        exec java -jar "$REPO_DIR/loader.jar"
        ;;
    --trust-ca|-t)
        CERT_URL="http://127.0.0.1:8080/cert"
        echo "Checking for running Burp Suite proxy at $CERT_URL..."
        if ! curl -s -f -m 3 "$CERT_URL" -o /dev/null 2>/dev/null; then
            if ! pgrep -f "$JAR_NAME" >/dev/null 2>&1 && ! pgrep -f 'burpsuite.*\.jar' >/dev/null 2>&1 && ! pgrep -f 'net\.portswigger' >/dev/null 2>&1; then
                echo "Burp Suite process is not running. Starting Burp in background..."
                nohup "$0" >/dev/null 2>&1 & disown 2>/dev/null || true
            else
                echo "Burp Suite process is running, waiting for proxy listener..."
            fi

            echo "Waiting for Burp proxy at $CERT_URL to become active (up to 90 seconds)..."
            burp_ready=false
            for ((attempt=1; attempt<=18; attempt++)); do
                sleep 5
                if curl -s -f -m 3 "$CERT_URL" -o /dev/null 2>/dev/null; then
                    burp_ready=true
                    echo "[✓] Burp proxy is active (detected after $((attempt * 5)) seconds)!"
                    break
                fi
                printf "  Waiting for proxy... (%d/18 attempts)\n" "$attempt"
            done

            if [ "$burp_ready" = false ]; then
                echo "ERROR: Burp proxy on http://127.0.0.1:8080 was not ready after 90 seconds." >&2
                echo "Please ensure Burp Suite is running with proxy listener on 127.0.0.1:8080, then re-run 'burpsuitepro --trust-ca'." >&2
                exit 1
            fi
        else
            echo "[✓] Burp proxy is active."
        fi

        tmp_der="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.der")"
        tmp_crt="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.crt")"
        cleanup() {
            rm -f "${tmp_der:-}" "${tmp_crt:-}"
        }
        trap cleanup EXIT INT TERM

        echo "Downloading CA certificate from Burp Suite proxy..."
        if ! curl -sSL --connect-timeout 5 --max-time 15 "$CERT_URL" -o "$tmp_der" || [ ! -s "$tmp_der" ]; then
            echo "ERROR: Failed to download CA certificate from $CERT_URL." >&2
            exit 1
        fi

        echo "Converting certificate to CRT format..."
        if ! openssl x509 -inform DER -in "$tmp_der" -out "$tmp_crt" 2>/dev/null; then
            echo "ERROR: Failed to convert DER certificate using openssl." >&2
            exit 1
        fi

        # 1. Detect and configure browsers first
        if command -v certutil &>/dev/null; then
            B_NAMES=()
            B_DETAILS=()
            B_PATHS=()

            detect_b() {
                local bname="$1"
                shift
                local search_dirs=()
                for d in "$@"; do
                    [ -d "$d" ] && search_dirs+=("$d")
                done
                [ ${#search_dirs[@]} -eq 0 ] && return

                local profiles=()
                while IFS= read -r db; do
                    [ -n "$db" ] && profiles+=("$(dirname "$db")")
                done < <(find "${search_dirs[@]}" -name "cert9.db" 2>/dev/null)

                if [ ${#profiles[@]} -gt 0 ]; then
                    B_NAMES+=("$bname")
                    local count=${#profiles[@]}
                    [ "$count" -eq 1 ] && B_DETAILS+=("found 1 profile") || B_DETAILS+=("found $count profiles")
                    local joined
                    joined="$(IFS=:; echo "${profiles[*]}")"
                    B_PATHS+=("$joined")
                fi
            }

            detect_b "Firefox" "$HOME/.mozilla" "$HOME/.config/mozilla" "$HOME/.var/app/org.mozilla.firefox"
            detect_b "Zen Browser" "$HOME/.zen" "$HOME/.config/zen" "$HOME/.var/app/io.github.zen_browser.zen" "$HOME/.var/app/app.zen_browser.zen"
            detect_b "LibreWolf" "$HOME/.librewolf" "$HOME/.config/librewolf" "$HOME/.var/app/io.gitlab.librewolf-community"
            detect_b "Floorp" "$HOME/.floorp" "$HOME/.config/floorp" "$HOME/.var/app/one.ablaze.floorp"
            detect_b "Waterfox" "$HOME/.waterfox" "$HOME/.config/waterfox" "$HOME/.var/app/net.waterfox.waterfox"

            if [ ${#B_NAMES[@]} -gt 0 ]; then
                TRUST_ALL=false
                FORCE_CLI=false
                for arg in "$@"; do
                    if [ "$arg" = "--all" ] || [ "$arg" = "-a" ] || [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
                        TRUST_ALL=true
                    elif [ "$arg" = "--cli" ]; then
                        FORCE_CLI=true
                    fi
                done
                if [ ! -t 0 ] && [ ! -c /dev/tty ]; then
                    TRUST_ALL=true
                fi

                selected_indices=()
                if [ "$TRUST_ALL" = true ]; then
                    echo "Selecting all detected browsers."
                    for ((idx=0; idx<${#B_NAMES[@]}; idx++)); do
                        selected_indices+=("$idx")
                    done
                elif [ "$FORCE_CLI" = false ] && [ -c /dev/tty ] && (command -v dialog &>/dev/null || command -v whiptail &>/dev/null); then
                    tui_items=(
                        "ALL" "--> All detected browsers (Default)" "ON"
                    )
                    for i in "${!B_NAMES[@]}"; do
                        tui_items+=("$((i + 1))" "${B_NAMES[i]} (${B_DETAILS[i]})" "OFF")
                    done
                    tui_items+=("NONE" "--> None (OS System Store only)" "OFF")

                    term_lines=$(tput lines 2>/dev/null || echo 24)
                    term_cols=$(tput cols 2>/dev/null || echo 80)
                    [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=24
                    [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80

                    box_width=72
                    [ "$term_cols" -lt 78 ] && box_width=$((term_cols - 6))
                    [ "$box_width" -lt 40 ] && box_width=40

                    total_items=$((${#tui_items[@]} / 3))
                    box_height=$((total_items + 9))
                    [ "$box_height" -gt $((term_lines - 4)) ] && box_height=$((term_lines - 4))
                    [ "$box_height" -lt 14 ] && box_height=14
                    list_height=$total_items
                    [ "$list_height" -gt $((box_height - 7)) ] && list_height=$((box_height - 7))
                    [ "$list_height" -lt 4 ] && list_height=4

                    tui_raw=""
                    tui_rc=0
                    if command -v dialog &>/dev/null; then
                        tui_raw=$(dialog --no-hot-list --stdout \
                            --title "Burp Suite CA Certificate - Browser Selection" \
                            --checklist "Select browsers to trust the Burp CA certificate:\n(Use SPACE to select/deselect, ENTER to confirm)" \
                            "$box_height" "$box_width" "$list_height" "${tui_items[@]}" </dev/tty) || tui_rc=$?
                    elif command -v whiptail &>/dev/null; then
                        tui_raw=$(whiptail \
                            --title "Burp Suite CA Certificate - Browser Selection" \
                            --checklist "Select browsers to trust the Burp CA certificate:\n(Use SPACE to select/deselect, ENTER to confirm)" \
                            "$box_height" "$box_width" "$list_height" "${tui_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || tui_rc=$?
                    fi

                    if [ "$tui_rc" -eq 1 ] || [ "$tui_rc" -eq 255 ]; then
                        echo "Certificate trust cancelled by user."
                        exit 0
                    fi

                    parsed_tags=()
                    for token in $(echo "$tui_raw" | tr -d '",'); do
                        [ -n "$token" ] && parsed_tags+=("$token")
                    done

                    has_all=false
                    has_none=false
                    numeric_tags=()

                    for tag in "${parsed_tags[@]}"; do
                        if [ "$tag" = "ALL" ]; then
                            has_all=true
                        elif [ "$tag" = "NONE" ]; then
                            has_none=true
                        elif [[ "$tag" =~ ^[0-9]+$ ]] && [ "$tag" -ge 1 ] && [ "$tag" -le "${#B_NAMES[@]}" ]; then
                            numeric_tags+=("$((tag - 1))")
                        fi
                    done

                    if [ "$has_none" = true ]; then
                        echo "Skipping browser trust store installation (NONE selected)."
                    elif [ "$has_all" = true ]; then
                        echo "Selecting all detected browsers."
                        for ((idx=0; idx<${#B_NAMES[@]}; idx++)); do
                            selected_indices+=("$idx")
                        done
                    elif [ ${#numeric_tags[@]} -gt 0 ]; then
                        selected_indices=("${numeric_tags[@]}")
                    else
                        echo "No browsers selected; skipping browser profile injection."
                    fi
                else
                    echo ""
                    echo "=== Detected Browsers ==="
                    for i in "${!B_NAMES[@]}"; do
                        echo "  [$((i + 1))] ${B_NAMES[i]} (${B_DETAILS[i]})"
                    done
                    echo "  -------------------------------------"
                    echo "  [A] All detected browsers (Default)"
                    echo "  [N] None (OS System Store only)"
                    echo ""

                    while true; do
                        printf "Select browsers to trust [A/N or numbers like 1,2] (Default: A): "
                        choice=""
                        if [ -e /dev/tty ]; then
                            IFS= read -r choice </dev/tty || choice="A"
                        else
                            IFS= read -r choice || choice="A"
                        fi
                        choice="$(echo "$choice" | xargs)"

                        case "${choice^^}" in
                            ""|"A"|"ALL")
                                for ((idx=0; idx<${#B_NAMES[@]}; idx++)); do
                                    selected_indices+=("$idx")
                                done
                                break
                                ;;
                            "N"|"NONE")
                                echo "Skipping browser trust store installation (keeping OS system store)."
                                break
                                ;;
                            *)
                                invalid=false
                                cleaned="${choice//,/ }"
                                temp_indices=()
                                for tok in $cleaned; do
                                    if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#B_NAMES[@]}" ]; then
                                        temp_indices+=("$((tok - 1))")
                                    else
                                        echo "Invalid selection: '$tok'. Please enter numbers between 1 and ${#B_NAMES[@]}, A, or N."
                                        invalid=true
                                        break
                                    fi
                                done
                                if [ "$invalid" = false ] && [ ${#temp_indices[@]} -gt 0 ]; then
                                    selected_indices=("${temp_indices[@]}")
                                    break
                                fi
                                ;;
                        esac
                    done
                fi

                # Deduplicate selections
                unique_indices=()
                for idx in "${selected_indices[@]}"; do
                    already=false
                    for u in "${unique_indices[@]}"; do
                        if [ "$u" -eq "$idx" ]; then already=true; break; fi
                    done
                    [ "$already" = false ] && unique_indices+=("$idx")
                done

                for sel_idx in "${unique_indices[@]}"; do
                    b_name="${B_NAMES[sel_idx]}"
                    echo "Installing Burp CA certificate into $b_name..."
                    IFS=: read -r -a paths <<< "${B_PATHS[sel_idx]}"
                    for p in "${paths[@]}"; do
                        if [ -d "$p" ]; then
                            if certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "sql:$p" 2>/dev/null; then
                                echo "  [✓] Imported into profile: $p"
                            elif certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "dbm:$p" 2>/dev/null; then
                                echo "  [✓] Imported into profile (dbm): $p"
                            else
                                echo "  [!] Warning: Failed to import into profile: $p (browser may be open and locking cert9.db)" >&2
                            fi
                        fi
                    done
                done
            else
                echo "No supported browser profiles detected."
            fi
        else
            echo "Note: certutil (libnss3-tools) is not installed. Skipping direct browser profile injection."
        fi

        # 2. Install to OS System Trust Store & Enterprise Roots
        echo "Installing CA certificate to system trust store (requires sudo)..."
        sys_cert_dir="/usr/local/share/ca-certificates"
        sys_cert="$sys_cert_dir/burpsuite-ca.crt"
        sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
        if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo update-ca-certificates; then
            echo "[✓] System trust store updated ($sys_cert)."
        else
            echo "[!] Failed to update system trust store." >&2
        fi

        echo "Configuring browser Enterprise Roots policy..."
        update_enterprise_roots() {
            local pdir="$1"
            local pfile="$pdir/policies.json"
            sudo mkdir -p "$pdir" 2>/dev/null || true
            if [ -d "$pdir" ]; then
                local tmp_pol
                tmp_pol="$(mktemp "${TMPDIR:-/tmp}/burp-pol-XXXXXX.json")"
                if [ -f "$pfile" ]; then
                    python3 -c "
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, 'r', encoding='utf-8') as f:
        d = json.load(f)
except Exception:
    d = {}
if not isinstance(d, dict): d = {}
p = d.setdefault('policies', {})
if isinstance(p, dict): p['ImportEnterpriseRoots'] = True
with open(dst, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$pfile" "$tmp_pol" 2>/dev/null || printf '{\n  "policies": {\n    "ImportEnterpriseRoots": true\n  }\n}\n' > "$tmp_pol"
                else
                    printf '{\n  "policies": {\n    "ImportEnterpriseRoots": true\n  }\n}\n' > "$tmp_pol"
                fi
                sudo cp "$tmp_pol" "$pfile" 2>/dev/null || true
                sudo chmod 644 "$pfile" 2>/dev/null || true
                rm -f "$tmp_pol"
            fi
        }

        for pdir in /etc/firefox/policies /etc/librewolf/policies /etc/floorp/policies /etc/waterfox/policies /etc/zen/policies; do
            update_enterprise_roots "$pdir"
        done

        echo ""
        echo "[✓] Burp Suite CA certificate successfully installed and trusted!"
        exit 0
        ;;
    --version|-v)
        echo "Burp Suite Professional: $BURP_VERSION"
        echo "JAR: $REPO_DIR/$JAR_NAME"
        exit 0
        ;;
    --path|-p)
        echo "$REPO_DIR"
        exit 0
        ;;
    --help|-h)
        echo "Usage: burpsuitepro [OPTIONS] [BURP_ARGS...]"
        echo ""
        echo "Options:"
        echo "  -k, --keygen    Launch Burp Suite key loader / keygen"
        echo "  -t, --trust-ca [--all|--cli]  Export and install Burp CA certificate into system & browser trust stores"
        echo "  -v, --version   Display current Burp Suite version and JAR filename"
        echo "  -p, --path      Display install directory path"
        echo "  -h, --help      Show launcher usage"
        echo ""
        echo "All other arguments are passed through to Burp Suite."
        exit 0
        ;;
esac

exec java \
  --add-opens=java.desktop/javax.swing=ALL-UNNAMED \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED \
  -XX:MaxRAMPercentage=50 \
  -XX:+UseG1GC \
  -Dawt.useSystemAAFontSettings=on \
  -Dswing.aatext=true \
  -Dsun.java2d.uiScale=auto \
  -javaagent:"$REPO_DIR/loader.jar" \
  -noverify \
  -jar "$REPO_DIR/$JAR_NAME" "$@"
EOF
chmod +x "$LAUNCHER_PATH"

if [[ -w /usr/local/bin ]]; then
    ln -sf "$LAUNCHER_PATH" /usr/local/bin/burpsuitepro 2>/dev/null || true
elif command -v sudo &>/dev/null; then
    sudo -n ln -sf "$LAUNCHER_PATH" /usr/local/bin/burpsuitepro 2>/dev/null || sudo ln -sf "$LAUNCHER_PATH" /usr/local/bin/burpsuitepro 2>/dev/null || true
fi

# 7. Create Desktop Shortcut
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

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

# 8. Start Key Loader & Burp Suite Pro
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

# Check if Burp Suite proxy is active or wait for it to become active before offering CA certificate trust
BURP_CERT_URL="http://127.0.0.1:8080/cert"
burp_proxy_active=false

if curl -s -f -m 2 "$BURP_CERT_URL" -o /dev/null 2>/dev/null; then
    burp_proxy_active=true
elif [ "$SKIP_LAUNCH" = false ]; then
    echo ""
    echo "Waiting for Burp Suite proxy to start at $BURP_CERT_URL (up to 60 seconds)..."
    for ((attempt=1; attempt<=12; attempt++)); do
        sleep 5
        if curl -s -f -m 3 "$BURP_CERT_URL" -o /dev/null 2>/dev/null; then
            burp_proxy_active=true
            echo "[✓] Burp proxy is active (detected after $((attempt * 5)) seconds)!"
            break
        fi
        printf "  Waiting for Burp proxy... (%d/12 attempts)\n" "$attempt"
    done
fi

if [ "$burp_proxy_active" = true ]; then
    echo ""
    echo "=================================================="
    echo "     Burp Suite CA Certificate Auto-Trust         "
    echo "=================================================="
    echo "Active Burp Suite proxy detected on http://127.0.0.1:8080."
    do_trust=""
    if [ -t 0 ] || [ -e /dev/tty ]; then
        read -rp "Would you like to install & trust Burp CA certificate now in browsers? [Y/n]: " do_trust </dev/tty || do_trust="Y"
    else
        do_trust="Y"
    fi
    case "${do_trust,,}" in
    "" | y | yes)
        "$LAUNCHER_PATH" --trust-ca || true
        ;;
    *)
        echo "Skipping certificate trust setup. You can run 'burpsuitepro --trust-ca' anytime."
        ;;
    esac
else
    echo ""
    echo "To auto-install & trust Burp CA certificate across Firefox, Zen Browser, LibreWolf, Floorp, Waterfox:"
    echo "  1. Launch Burp Suite: burpsuitepro"
    echo "  2. Run in a terminal: burpsuitepro --trust-ca"
fi
