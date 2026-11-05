#!/usr/bin/env bash
# ============================================================================
# Universal Burp Suite Professional Shared Core Installer
# ============================================================================

set -euo pipefail

BURP_STABLE_VERSION="2026.10.1"
REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
JYTHON_URL="https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"
JYTHON_JAR="jython-standalone-2.7.4.jar"
JYTHON_FILE="$REPO_DIR/$JYTHON_JAR"

LOADER_URLS=(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
    "https://raw.githubusercontent.com/xiv3r/Burpsuite-Professional/main/loader.jar"
)

# Helper function to find burp binary
find_burp_bin() {
    if [ -n "${BURP_BIN:-}" ] && [ "$BURP_BIN" != "none" ] && [ -x "$BURP_BIN" ]; then
        echo "$BURP_BIN"
        return 0
    fi
    local b
    for b in "$HOME/.local/bin/burpsuitepro" "/usr/local/bin/burpsuitepro" "$HOME/Documents/Crack/Burpsuite-Professional/burpsuitepro"; do
        if [ -x "$b" ]; then
            echo "$b"
            return 0
        fi
    done
    return 1
}

# Helper function to get file size in bytes
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# Helper function to compare version strings: returns 0 (true) if $1 >= $2
version_ge() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Pre-seed JRE Warning Suppression
suppress_jre_warnings() {
    echo "Configuring JRE warning suppression..."
    local prefs_dir="$HOME/.java/.userPrefs/burp"
    local prefs_file="$prefs_dir/prefs.xml"
    mkdir -p "$prefs_dir"

    local entries=(
        "suite.alertsdisabledforjre-3189538875"
        "suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-3189538875"
        "burp.suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-1872878544"
        "burp.suite.alertsdisabledforjre-413592390"
    )

    if [[ ! -f "$prefs_file" || ! -s "$prefs_file" || $(grep -c "</map>" "$prefs_file" 2>/dev/null || echo 0) -eq 0 ]]; then
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
        for key in "${entries[@]}"; do
            if ! grep -qF "key=\"$key\"" "$prefs_file"; then
                sed -i "/<\/map>/i \  <entry key=\"$key\" value=\"true\"/>" "$prefs_file"
            fi
        done
    fi
    echo "JRE warning suppression configured."
}

# Verify unprivileged user namespaces on Arch
burp_check_user_namespaces() {
    echo "Checking unprivileged user namespaces for embedded Chromium..."
    local userns_ok=true

    if [[ -f /proc/sys/kernel/unprivileged_userns_clone ]] && [[ "$(</proc/sys/kernel/unprivileged_userns_clone)" -eq 0 ]]; then
        userns_ok=false
    fi

    if [[ -f /proc/sys/user/max_user_namespaces ]] && [[ "$(</proc/sys/user/max_user_namespaces)" -eq 0 ]]; then
        userns_ok=false
    fi

    if ! unshare --user true 2>/dev/null; then
        userns_ok=false
    fi

    if [[ "$userns_ok" == false ]]; then
        echo "[!] Warning: Unprivileged user namespaces appear disabled or restricted."
        echo "    Burp Suite's embedded Chromium browser requires user namespaces to sandbox."
        echo "    Enable them with: sudo sysctl -w kernel.unprivileged_userns_clone=1"
        echo "    Or persist via /etc/sysctl.d/00-local-userns.conf (kernel.unprivileged_userns_clone = 1)"
    else
        echo "Unprivileged user namespaces verified (embedded Chromium sandbox supported)."
    fi
}

# Verify unprivileged user namespaces on Debian / Kali
burp_enable_debian_userns() {
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
}

burp_usage() {
    cat <<EOF
Usage: install.sh [OPTIONS] [VERSION]

Install Burp Suite Professional with selectable version channel.

Options:
  -v, --version <ver>   Install an exact version (e.g. 2026.10.1)
      --channel <name>  Version channel: stable (tested) or latest (UNTESTED)
  -f, --force           Re-download even if files already exist
      --skip-launch     Install without launching Burp Suite
  -h, --help            Show this help and exit

Environment:
  BURP_VERSION          Same as --version; -v takes precedence
EOF
}

run_burp_installation() {
    local distro_label="$1"
    local dep_func="$2"
    local sandbox_func="$3"
    shift 3

    local skip_launch=false
    local force_download=false
    local custom_version=""
    local channel=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                burp_usage
                exit 0
                ;;
            -v | --version)
                if [[ $# -lt 2 ]]; then
                    echo "ERROR: $1 requires a version argument." >&2
                    exit 1
                fi
                custom_version="$2"
                shift 2
                ;;
            --skip-launch)
                skip_launch=true
                shift
                ;;
            -f | --force)
                force_download=true
                shift
                ;;
            --channel)
                if [[ $# -lt 2 ]]; then
                    echo "ERROR: $1 requires a channel argument (stable or latest)." >&2
                    exit 1
                fi
                channel="$2"
                shift 2
                ;;
            *)
                if [[ -z "$custom_version" && "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                    custom_version="$1"
                fi
                shift
                ;;
        esac
    done

    # Version resolution
    local burp_ver=""
    if [[ -n "$custom_version" ]]; then
        burp_ver="$custom_version"
        echo "Using specified Burp Suite version: $burp_ver"
    elif [[ -n "${BURP_VERSION:-}" ]]; then
        burp_ver="$BURP_VERSION"
        echo "Using environment BURP_VERSION: $burp_ver"
    else
        channel="${channel:-stable}"
        channel="${channel,,}"
        if [[ "$channel" == "stable" ]]; then
            burp_ver="$BURP_STABLE_VERSION"
            echo "Using stable (tested) Burp Suite version: $burp_ver"
        elif [[ "$channel" == "latest" ]]; then
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║  ⚠  WARNING: Latest channel selected (UNTESTED)            ║"
            echo "║  This fetches the newest release from PortSwigger.          ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo "Fetching latest Burp Suite version from PortSwigger..."
            burp_ver="$(curl -sSL --connect-timeout 10 --max-time 15 'https://portswigger.net/burp/releases/data?pageSize=10' 2>/dev/null | python3 -c "
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

            if [[ -z "$burp_ver" ]]; then
                echo "PortSwigger API unavailable, checking GitHub release..."
                burp_ver="$(curl -sSL --connect-timeout 10 --max-time 15 'https://api.github.com/repos/xiv3r/Burpsuite-Professional/releases/latest' 2>/dev/null | python3 -c "
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

            if [[ -z "$burp_ver" ]]; then
                burp_ver="$BURP_STABLE_VERSION"
                echo "APIs unavailable. Falling back to stable version: $burp_ver"
            else
                echo "Latest version detected: $burp_ver"
            fi
        else
            echo "ERROR: Invalid channel '$channel'. Use 'stable' or 'latest'." >&2
            exit 1
        fi
    fi

    local jar_name="burpsuite_pro_v${burp_ver}.jar"
    local download_url="https://portswigger.net/burp/releases/download?product=desktop&version=${burp_ver}&type=Jar"

    echo "=== Installing Burp Suite Professional ($distro_label) ==="

    # Check for active running instances
    if pgrep -f 'burpsuite_pro_v.*\.jar' >/dev/null 2>&1; then
        echo "[!] Warning: Burp Suite Professional is currently running."
        echo "Please close Burp Suite to avoid file lock issues."
        if [ -t 0 ]; then
            read -rp "Press Enter once Burp Suite is closed, or Ctrl+C to cancel..." || true
        fi
    fi

    # 1. Install dependencies & run sandbox check
    if declare -f "$dep_func" >/dev/null 2>&1; then
        "$dep_func"
    fi
    if declare -f "$sandbox_func" >/dev/null 2>&1; then
        "$sandbox_func"
    fi

    # 2. Setup install directory
    mkdir -p "$REPO_DIR"

    # Download loader.jar
    local loader_file="$REPO_DIR/loader.jar"
    if [[ -f "$loader_file" && $(get_file_size "$loader_file") -gt 10240 && "$force_download" == false ]]; then
        echo "Existing loader.jar verified (> 10KB). Skipping download."
    else
        echo "Downloading loader.jar..."
        local loader_downloaded=false
        local url
        for url in "${LOADER_URLS[@]}"; do
            echo "Attempting loader download from: $url"
            if curl -fL --connect-timeout 10 --max-time 60 --progress-bar -o "$loader_file.tmp" "$url" 2>/dev/null; then
                if [[ $(get_file_size "$loader_file.tmp") -gt 10240 ]]; then
                    mv "$loader_file.tmp" "$loader_file"
                    echo "Successfully downloaded loader.jar"
                    loader_downloaded=true
                    break
                else
                    rm -f "$loader_file.tmp"
                fi
            fi
        done
        if [[ "$loader_downloaded" == false ]]; then
            if [[ -f "$loader_file" && $(get_file_size "$loader_file") -gt 10240 ]]; then
                echo "WARNING: Failed to re-download loader.jar, preserving existing valid file."
            else
                echo "ERROR: Failed to download loader.jar from all mirrors." >&2
                exit 1
            fi
        fi
    fi

    # 3. Download Burp Suite Pro JAR
    cd "$REPO_DIR"
    local skip_download=false
    local min_jar_size=10485760 # 10MB
    local target_jar="$REPO_DIR/$jar_name"

    if [[ "$force_download" == false ]]; then
        local target_size
        target_size="$(get_file_size "$target_jar")"
        if [[ -f "$target_jar" && "$target_size" -gt $min_jar_size ]]; then
            echo "Burp Suite Professional v$burp_ver ($jar_name) already present and valid ($((target_size / 1024 / 1024))MB)."
            skip_download=true
        elif compgen -G "$REPO_DIR/burpsuite_pro_v*.jar" >/dev/null; then
            local latest_valid_jar=""
            local latest_valid_ver=""
            while IFS= read -r candidate; do
                [[ -z "$candidate" || ! -f "$candidate" ]] && continue
                local cand_size
                cand_size="$(get_file_size "$candidate")"
                if [[ "$cand_size" -gt $min_jar_size ]]; then
                    latest_valid_jar="$candidate"
                    latest_valid_ver="$(basename "$candidate" | sed -E 's/^burpsuite_pro_v(.*)\.jar$/\1/')"
                fi
            done < <(find "$REPO_DIR" -maxdepth 1 -name 'burpsuite_pro_v*.jar' 2>/dev/null | sort -V)

            if [[ -n "$latest_valid_jar" ]]; then
                if version_ge "$latest_valid_ver" "$burp_ver"; then
                    echo "Found installed version $latest_valid_ver, which is >= requested $burp_ver. Skipping download."
                    skip_download=true
                    jar_name="$(basename "$latest_valid_jar")"
                    burp_ver="$latest_valid_ver"
                else
                    echo "Found older version ($latest_valid_ver). Upgrading to $burp_ver..."
                fi
            fi
        fi
    fi

    if [[ "$skip_download" == false ]]; then
        echo "Downloading Burp Suite Professional $burp_ver ($jar_name)..."
        local jar_downloaded=false
        if command -v aria2c &>/dev/null; then
            echo "Using aria2c accelerator (16 connections)..."
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$jar_name.tmp" "$download_url"; then
                if [[ -f "$jar_name.tmp" && $(get_file_size "$jar_name.tmp") -gt $min_jar_size ]]; then
                    jar_downloaded=true
                fi
            fi
            rm -f "$REPO_DIR/$jar_name.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$jar_downloaded" == false ]] && command -v curl &>/dev/null; then
            echo "Using curl with auto-resume..."
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$jar_name.tmp" "$download_url"; then
                if [[ -f "$jar_name.tmp" && $(get_file_size "$jar_name.tmp") -gt $min_jar_size ]]; then
                    jar_downloaded=true
                fi
            fi
        fi
        if [[ "$jar_downloaded" == false ]] && command -v wget &>/dev/null; then
            echo "Using wget fallback..."
            if wget -O "$jar_name.tmp" --quiet --show-progress "$download_url"; then
                if [[ -f "$jar_name.tmp" && $(get_file_size "$jar_name.tmp") -gt $min_jar_size ]]; then
                    jar_downloaded=true
                fi
            fi
        fi

        if [[ "$jar_downloaded" == false || ! -f "$jar_name.tmp" || $(get_file_size "$jar_name.tmp") -le $min_jar_size ]]; then
            echo "ERROR: Failed to download valid Burp Suite JAR file." >&2
            rm -f "$jar_name.tmp" "$REPO_DIR/$jar_name.tmp.aria2" 2>/dev/null || true
            exit 1
        fi

        mv -f "$jar_name.tmp" "$jar_name"

        # Backup older Burp JARs
        for old_jar in "$REPO_DIR"/burpsuite_pro_v*.jar; do
            if [[ -f "$old_jar" && "$(basename "$old_jar")" != "$jar_name" ]]; then
                mv -f "$old_jar" "${old_jar}.bk"
            fi
        done
    fi

    # Display checksums
    if [[ -f "$jar_name" ]]; then
        echo "--- File Checksums ---"
        echo "SHA256: $(sha256sum "$jar_name" | cut -d' ' -f1)"
        echo "MD5:    $(md5sum "$jar_name" | cut -d' ' -f1)"
    fi

    # 4. Copy local assets
    local core_dir
    core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "Copying shared configuration and icon..."
    if [[ -f "$core_dir/burp/.config.ini" ]]; then
        cp "$core_dir/burp/.config.ini" "$REPO_DIR/" 2>/dev/null || true
    fi
    if [[ -f "$core_dir/burp/burp_suite_pro_icon.svg" ]]; then
        cp "$core_dir/burp/burp_suite_pro_icon.svg" "$REPO_DIR/" 2>/dev/null || true
    fi
    if [[ -f "$core_dir/burp-trust-ca.sh" ]]; then
        cp "$core_dir/burp-trust-ca.sh" "$REPO_DIR/burp-trust-ca.sh"
        chmod +x "$REPO_DIR/burp-trust-ca.sh"
    fi

    suppress_jre_warnings

    # 5. Jython Standalone & User Config
    echo "Configuring Jython Standalone 2.7.4..."
    local min_jython_size=20971520 # 20MB
    local jython_size
    jython_size="$(get_file_size "$JYTHON_FILE")"
    if [[ -f "$JYTHON_FILE" && "$jython_size" -gt $min_jython_size && "$force_download" == false ]]; then
        echo "Existing Jython standalone verified ($((jython_size / 1024 / 1024))MB)."
    else
        echo "Downloading Jython Standalone 2.7.4..."
        local download_ok=false
        if command -v aria2c &>/dev/null; then
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$JYTHON_JAR.tmp" "$JYTHON_URL" 2>/dev/null; then
                if [[ -f "$JYTHON_FILE.tmp" && $(get_file_size "$JYTHON_FILE.tmp") -gt $min_jython_size ]]; then
                    download_ok=true
                fi
            fi
            rm -f "$JYTHON_FILE.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$download_ok" == false ]] && command -v curl &>/dev/null; then
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$JYTHON_FILE.tmp" "$JYTHON_URL"; then
                if [[ -f "$JYTHON_FILE.tmp" && $(get_file_size "$JYTHON_FILE.tmp") -gt $min_jython_size ]]; then
                    download_ok=true
                fi
            fi
        fi
        if [[ "$download_ok" == false ]] && command -v wget &>/dev/null; then
            if wget -O "$JYTHON_FILE.tmp" --quiet --show-progress "$JYTHON_URL"; then
                if [[ -f "$JYTHON_FILE.tmp" && $(get_file_size "$JYTHON_FILE.tmp") -gt $min_jython_size ]]; then
                    download_ok=true
                fi
            fi
        fi

        if [[ "$download_ok" == true && -f "$JYTHON_FILE.tmp" && $(get_file_size "$JYTHON_FILE.tmp") -gt $min_jython_size ]]; then
            mv -f "$JYTHON_FILE.tmp" "$JYTHON_FILE"
            echo "Successfully downloaded $JYTHON_JAR."
        else
            rm -f "$JYTHON_FILE.tmp" 2>/dev/null || true
        fi
    fi

    if [[ -f "$JYTHON_FILE" && $(get_file_size "$JYTHON_FILE") -gt $min_jython_size ]]; then
        echo "Configuring Burp Suite User Config for Jython..."
        python3 - "$JYTHON_FILE" <<'PYEOF'
import json, os, sys
jython_path = sys.argv[1]
config_dir = os.path.expanduser("~/.BurpSuite")
os.makedirs(config_dir, exist_ok=True)
for cfg in ("UserConfigPro.json", "UserConfig.json"):
    cf = os.path.join(config_dir, cfg)
    data = {}
    if os.path.isfile(cf):
        try:
            with open(cf, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}
    if not isinstance(data, dict): data = {}
    uo = data.setdefault("user_options", {})
    if not isinstance(uo, dict): uo = {}; data["user_options"] = uo
    ext = uo.setdefault("extender", {})
    if not isinstance(ext, dict): ext = {}; uo["extender"] = ext
    py = ext.setdefault("python", {})
    if not isinstance(py, dict): py = {}; ext["python"] = py
    py["location_of_jython_standalone_jar_file"] = jython_path
    tmp = cf + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, cf)
PYEOF
        echo "Jython 2.7.4 configured."
    fi

    # 6. Create clean launcher binary
    mkdir -p "$HOME/.local/bin"
    local launcher_path="$HOME/.local/bin/burpsuitepro"

    echo "Creating launcher script at $launcher_path..."
    cat <<EOF >"$launcher_path"
#!/bin/bash
# Wayland and tiling WM compatibility
export _JAVA_AWT_WM_NONREPARENTING=1
if [ -z "\${DISPLAY:-}" ]; then
    if [ -n "\${WAYLAND_DISPLAY:-}" ] || [ -e /tmp/.X11-unix/X0 ]; then
        export DISPLAY=:0
    fi
fi

REPO_DIR="$REPO_DIR"
JAR_NAME="$jar_name"
BURP_VERSION="$burp_ver"

case "\${1:-}" in
    -k|--keygen)
        echo "Starting Burp Suite Keygen / Loader..."
        exec java -jar "\$REPO_DIR/loader.jar"
        ;;
    -v|--version)
        echo "Burp Suite Professional v\$BURP_VERSION (\$JAR_NAME)"
        exit 0
        ;;
    -p|--path)
        echo "\$REPO_DIR"
        exit 0
        ;;
    -t|--trust-ca)
        shift
        if [ -x "\$REPO_DIR/burp-trust-ca.sh" ]; then
            exec "\$REPO_DIR/burp-trust-ca.sh" "\$@"
        else
            echo "ERROR: CA trust script not found at \$REPO_DIR/burp-trust-ca.sh" >&2
            exit 1
        fi
        ;;
    -h|--help)
        cat <<'HLP'
Burp Suite Professional Launcher

Usage: burpsuitepro [OPTIONS] [BURP_ARGUMENTS...]

Options:
  -k, --keygen    Launch the key loader / keygen
  -v, --version   Display current Burp Suite version and JAR file
  -p, --path      Display Burp Suite installation directory path
  -t, --trust-ca  Auto-import Burp CA certificate into system & browsers
  -h, --help      Show this help message

All other arguments are passed directly to Burp Suite.
HLP
        exit 0
        ;;
esac

exec java \\
  --add-opens=java.desktop/javax.swing=ALL-UNNAMED \\
  --add-opens=java.base/java.lang=ALL-UNNAMED \\
  --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \\
  --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED \\
  --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED \\
  -XX:MaxRAMPercentage=50 \\
  -XX:+UseG1GC \\
  -Dawt.useSystemAAFontSettings=on \\
  -Dswing.aatext=true \\
  -Dsun.java2d.uiScale=auto \\
  -javaagent:"\$REPO_DIR/loader.jar" \\
  -noverify \\
  -jar "\$REPO_DIR/\$JAR_NAME" "\$@"
EOF
    chmod +x "$launcher_path"

    if [[ -w /usr/local/bin ]]; then
        ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || true
    elif command -v sudo &>/dev/null; then
        sudo -n ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || sudo ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || true
    fi

    # 7. Create desktop shortcut
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"
    local desktop_file="$desktop_dir/burpsuitepro.desktop"

    echo "Creating desktop entry at $desktop_file..."
    cat <<EOF >"$desktop_file"
[Desktop Entry]
Name=Burp Suite Professional
Comment=Burp Suite Professional - Web Application Security Testing
Exec=$launcher_path
Icon=$REPO_DIR/burp_suite_pro_icon.svg
Terminal=false
Type=Application
Categories=Network;Security;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
StartupWMClass=burp-StartBurp
EOF
    update-desktop-database "$desktop_dir" 2>/dev/null || true

    # 8. Start Key Loader & Burp Suite Pro if not skipped
    if [[ "$skip_launch" == false ]]; then
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
        nohup "$launcher_path" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    else
        echo "Skipping application launch (--skip-launch specified)."
    fi

    echo "=== Burp Suite Professional ($distro_label) installation completed! ==="

    # Offer CA trust if active or standalone interactive
    if [[ "$skip_launch" == false ]]; then
        local cert_url="http://127.0.0.1:8080/cert"
        local cert_active=false

        if curl -s -f -m 2 "$cert_url" -o /dev/null 2>/dev/null; then
            cert_active=true
        else
            echo "Waiting for Burp Suite proxy listener (up to 45s)..."
            for ((att = 1; att <= 9; att++)); do
                sleep 5
                if curl -s -f -m 3 "$cert_url" -o /dev/null 2>/dev/null; then
                    cert_active=true
                    break
                fi
            done
        fi

        if [[ "$cert_active" == true ]]; then
            echo "Active Burp Suite proxy detected. Launching CA certificate trust..."
            "$launcher_path" --trust-ca || true
        else
            echo ""
            echo "To trust Burp CA certificate across browsers once Burp is running:"
            echo "  Run: burpsuitepro --trust-ca"
        fi
    fi
}
