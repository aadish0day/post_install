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
JRUBY_VERSION="9.4.9.0"
JRUBY_URL="https://repo1.maven.org/maven2/org/jruby/jruby-complete/${JRUBY_VERSION}/jruby-complete-${JRUBY_VERSION}.jar"
JRUBY_JAR="jruby-complete-${JRUBY_VERSION}.jar"
JRUBY_FILE="$REPO_DIR/$JRUBY_JAR"

LOADER_URLS=(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
)

# Helper function to find best Java 21 binary
find_java_bin() {
    local j
    for j in \
        "/usr/lib/jvm/java-21-openjdk/bin/java" \
        "/usr/lib/jvm/java-21-openjdk-amd64/bin/java" \
        "/usr/lib/jvm/default-runtime/bin/java"; do
        if [ -x "$j" ]; then
            echo "$j"
            return 0
        fi
    done
    if command -v java &>/dev/null; then
        echo "java"
        return 0
    fi
    echo "java"
}

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

# Install scalable and raster icons across user and system hicolor themes
install_burp_system_icons() {
    local svg_source="${1:-}"
    if [[ -z "$svg_source" || ! -f "$svg_source" ]]; then
        if [[ -f "$REPO_DIR/burp_suite_pro_icon.svg" ]]; then
            svg_source="$REPO_DIR/burp_suite_pro_icon.svg"
        else
            echo "Warning: Icon source SVG not found ($svg_source). Skipping icon installation."
            return 0
        fi
    fi

    echo "Installing Burp Suite system icons..."
    local user_icon_base="$HOME/.local/share/icons/hicolor"
    local user_pixmaps="$HOME/.local/share/pixmaps"
    mkdir -p "$user_icon_base/scalable/apps" "$user_pixmaps"

    cp -f "$svg_source" "$user_icon_base/scalable/apps/burpsuitepro.svg"
    cp -f "$svg_source" "$user_pixmaps/burpsuitepro.svg"

    local sizes=(16 24 32 48 64 128 256 512)
    local s
    for s in "${sizes[@]}"; do
        local user_size_dir="$user_icon_base/${s}x${s}/apps"
        mkdir -p "$user_size_dir"
        local target_png="$user_size_dir/burpsuitepro.png"
        if command -v rsvg-convert &>/dev/null; then
            rsvg-convert -w "$s" -h "$s" "$svg_source" -o "$target_png" 2>/dev/null || true
        elif command -v convert &>/dev/null; then
            convert -background none "$svg_source" -resize "${s}x${s}" "$target_png" 2>/dev/null || true
        elif command -v magick &>/dev/null; then
            magick "$svg_source" -background none -resize "${s}x${s}" "$target_png" 2>/dev/null || true
        fi
    done

    # System-wide installation if writable or passwordless sudo
    local sys_icon_base="/usr/local/share/icons/hicolor"
    local sys_pixmaps="/usr/share/pixmaps"

    if [[ -w /usr/local/share && -w "$sys_pixmaps" ]]; then
        mkdir -p "$sys_icon_base/scalable/apps" "$sys_pixmaps"
        cp -f "$svg_source" "$sys_icon_base/scalable/apps/burpsuitepro.svg" 2>/dev/null || true
        cp -f "$svg_source" "$sys_pixmaps/burpsuitepro.svg" 2>/dev/null || true
        for s in "${sizes[@]}"; do
            if [[ -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" ]]; then
                mkdir -p "$sys_icon_base/${s}x${s}/apps"
                cp -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" "$sys_icon_base/${s}x${s}/apps/burpsuitepro.png" 2>/dev/null || true
            fi
        done
        gtk-update-icon-cache -f -q -t "$sys_icon_base" 2>/dev/null || true
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -n mkdir -p "$sys_icon_base/scalable/apps" "$sys_pixmaps" 2>/dev/null || true
        sudo -n cp -f "$svg_source" "$sys_icon_base/scalable/apps/burpsuitepro.svg" 2>/dev/null || true
        sudo -n cp -f "$svg_source" "$sys_pixmaps/burpsuitepro.svg" 2>/dev/null || true
        for s in "${sizes[@]}"; do
            if [[ -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" ]]; then
                sudo -n mkdir -p "$sys_icon_base/${s}x${s}/apps" 2>/dev/null || true
                sudo -n cp -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" "$sys_icon_base/${s}x${s}/apps/burpsuitepro.png" 2>/dev/null || true
            fi
        done
        sudo -n gtk-update-icon-cache -f -q -t "$sys_icon_base" 2>/dev/null || true
    fi

    # Rebuild user icon cache
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -q -t "$user_icon_base" 2>/dev/null || true
    fi
}

# Install custom MIME type for Burp Suite project files
install_burp_system_mime() {
    echo "Installing Burp Suite project MIME type..."
    local user_mime_dir="$HOME/.local/share/mime/packages"
    mkdir -p "$user_mime_dir"

    cat <<'EOF' >"$user_mime_dir/burpsuitepro.xml"
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-burp-project">
    <comment>Burp Suite Project</comment>
    <icon name="burpsuitepro"/>
    <glob pattern="*.burp"/>
    <glob pattern="*.burpstate"/>
  </mime-type>
</mime-info>
EOF

    if command -v update-mime-database &>/dev/null; then
        update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    fi

    # System-wide MIME installation if writable or passwordless sudo
    local sys_mime_dir="/usr/local/share/mime/packages"
    if [[ -w /usr/local/share/mime ]]; then
        mkdir -p "$sys_mime_dir"
        cp -f "$user_mime_dir/burpsuitepro.xml" "$sys_mime_dir/burpsuitepro.xml" 2>/dev/null || true
        update-mime-database /usr/local/share/mime 2>/dev/null || true
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -n mkdir -p "$sys_mime_dir" 2>/dev/null || true
        sudo -n cp -f "$user_mime_dir/burpsuitepro.xml" "$sys_mime_dir/burpsuitepro.xml" 2>/dev/null || true
        sudo -n update-mime-database /usr/local/share/mime 2>/dev/null || true
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

    install_burp_system_icons "$REPO_DIR/burp_suite_pro_icon.svg"
    install_burp_system_mime

    suppress_jre_warnings

    # 5. Jython & JRuby Standalone Extensions & User Config
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

    echo "Configuring JRuby Standalone $JRUBY_VERSION..."
    local min_jruby_size=31457280 # 30MB
    local jruby_size
    jruby_size="$(get_file_size "$JRUBY_FILE")"
    if [[ -f "$JRUBY_FILE" && "$jruby_size" -gt $min_jruby_size && "$force_download" == false ]]; then
        echo "Existing JRuby standalone verified ($((jruby_size / 1024 / 1024))MB)."
    else
        echo "Downloading JRuby Standalone $JRUBY_VERSION..."
        local jruby_download_ok=false
        if command -v aria2c &>/dev/null; then
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$JRUBY_JAR.tmp" "$JRUBY_URL" 2>/dev/null; then
                if [[ -f "$JRUBY_FILE.tmp" && $(get_file_size "$JRUBY_FILE.tmp") -gt $min_jruby_size ]]; then
                    jruby_download_ok=true
                fi
            fi
            rm -f "$JRUBY_FILE.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$jruby_download_ok" == false ]] && command -v curl &>/dev/null; then
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$JRUBY_FILE.tmp" "$JRUBY_URL"; then
                if [[ -f "$JRUBY_FILE.tmp" && $(get_file_size "$JRUBY_FILE.tmp") -gt $min_jruby_size ]]; then
                    jruby_download_ok=true
                fi
            fi
        fi
        if [[ "$jruby_download_ok" == false ]] && command -v wget &>/dev/null; then
            if wget -O "$JRUBY_FILE.tmp" --quiet --show-progress "$JRUBY_URL"; then
                if [[ -f "$JRUBY_FILE.tmp" && $(get_file_size "$JRUBY_FILE.tmp") -gt $min_jruby_size ]]; then
                    jruby_download_ok=true
                fi
            fi
        fi

        if [[ "$jruby_download_ok" == true && -f "$JRUBY_FILE.tmp" && $(get_file_size "$JRUBY_FILE.tmp") -gt $min_jruby_size ]]; then
            mv -f "$JRUBY_FILE.tmp" "$JRUBY_FILE"
            echo "Successfully downloaded $JRUBY_JAR."
        else
            rm -f "$JRUBY_FILE.tmp" 2>/dev/null || true
        fi
    fi

    if [[ (-f "$JYTHON_FILE" && $(get_file_size "$JYTHON_FILE") -gt $min_jython_size) || (-f "$JRUBY_FILE" && $(get_file_size "$JRUBY_FILE") -gt $min_jruby_size) ]]; then
        echo "Configuring Burp Suite User Config for Jython & JRuby..."
        python3 - "$JYTHON_FILE" "$JRUBY_FILE" <<'PYEOF'
import json, os, sys
jython_path = sys.argv[1]
jruby_path = sys.argv[2]
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
    ruby = ext.setdefault("ruby", {})
    if not isinstance(ruby, dict): ruby = {}; ext["ruby"] = ruby
    ruby["location_of_jruby_jar_file"] = jruby_path
    tmp = cf + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, cf)
PYEOF
        echo "Jython 2.7.4 and JRuby 9.4.9.0 configured."
    fi

    # Pre-seed Burp Suite license & preferences so Burp launches without manual keygen prompts
    local prefs_dir="$HOME/.java/.userPrefs/burp"
    local prefs_file="$prefs_dir/prefs.xml"
    if [ ! -f "$prefs_file" ] || ! grep -q "license1" "$prefs_file" 2>/dev/null; then
        echo "Pre-seeding Burp Suite Professional license and preferences..."
        mkdir -p "$prefs_dir"
        cat <<'EOFPREFS' >"$prefs_file"
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="burp.eula" value="13"/>
  <entry key="use_community_edition" value="false"/>
  <entry key="suite.alertsdisabledforjre-1115054815" value="true"/>
  <entry key="suite.alertsdisabledforjre-3189538875" value="true"/>
  <entry key="license1" value="QKLM8/zjeX0FDxLCu5RTDbUc3jgF5M+7U+1qDz6yBjuvYAn2zh0uJq9gCfbOHS4mVlbyb7O0fZyFaQcK+3ebZC29Goqrc80aBZR6BQBSNDvdJqOWpxVZat/P1DHTsOB7cirx9E5NLm18OLtASpkVObKMOnfMiwYBBbqouffwTsxuqhOtj6ctAEjH92GhaVmYHSMHTuipOIEx38XYk+isqe4fYQGvpyOSW4/Ka96eY0fVQNzYUDnEnW5ecc0TG+dvW8jFwgo02yyQ+cLP+i8W8d96Kc8AopXsF67+60ceFTZobP8v3Otb7r6JAEK0TEIX7ZzHakGZTqad8sb559Lj5oHvt4dbkvNzJdrjNDe8OUYPWslw91/On6UQi41rEcj7lahwRRpdV9fYwAotUrHiu2YF87a8a5UXO0z0XvjA/6eKk7DAldfwcvtmDgH/NlzZuEVrO7AxMhGt4CNopbjkpqtXB3PxMB6J0ZOnyMbH/tFY9oLoir25KQr7TPFkfydK5Jbf1cz5UKk8lXfAf/lqBOZxcYoZnyocgSLm169Jx6ur42wTreOONfBFqWGtdAUBYuQwVBe3GS4xtV9F8nsu1P7iEBWwFo7TTU0duxNsr5NLMtqebrpvN1lWnRXlVnFOGuodWEZ5VTp4IxQbmDc2puBHO35TOubsivJlLa7zpD7nOgfLVpSdoU3DK0/lBqpZI75P6VjyXviGWvmp/n8dBKLvE4cOhCvTvm4wvEJOpMhgz3YGzqTf/6u1Kv7A9Kxv3STVHx4cBF5hpjLsiRG/lfeG+56CFTvLdXMzRFX0Y9M="/>
  <entry key="zRHyUR2Op7fIprORODg24A==" value="rbojo9jt6ZB24ppIimQBtBmKg228sphoRBryhZRnnpztuo5B0UqERnXyrKnEDFaaU1hUrjYaSgm8T2uGta23A0fdAgy15Rg7dzW1Du+TJqkzBnQzljo2tMOge1NHpJZ55ijGar+VxsqV4oDkWWKgNV3xz2rW1YyoiskDuk9pcCJcc2Q87RoG331t6HOdyhAJf8hCZRoALn/PaLu9g9puCMpDHUDwb1O9KhXjHkB0WuOpKOZyBeVXM9xJWXRwzHlKSOIwBXov3Cy1QMeb4Q3bnd8G1cpK76lqwzNavRycSVP1oxHZJJAPCZF2xk4kutYxKAtzV8pMkoYb5wqeo4lm73ee8hH6VDhZg+EWE+ll6gAAtONOltqkYiwYvkCkqtlOYKOM2YAMWwmknxRjkzh1tnyoWY2aeSDFzkj8SqasPkIZdVK8OBcd3vcRIBaGI47evaSkjA/d1cFClq2Oi/erkVN/zA75zZbfWt96rRIKhirMC2mVBQnyIXLt4VBsGgEjtZU5RvcYbhOf/zp4eNZOjAgB1kQrgoVHsb6PA8dfpoJ13zuuRn4Nwz1JH1uOdsM6CVSoZY9OnnD8ffAMWftJJ6tzLfa31yHLYwD/VzrfE3GaEd1Yh/3RTAy0y/ni9OzR0oGzy7FwDtC3j8UVnjeQqSN6fLL8Tnz57Neg5jWuyyKng6Npc0EW6s6u4S+l4nNMoNNNdaFWhSfo5xDRr6WOjdt+v6RGZevaa2fog50ImWDnmr6wsW0VTbyLf+Bg9V569QFpnTPBfRiFGDj36n5yNMn/GP+CqLDmGAVnVXmKoGjbwEq2HYbb9XNUPcpf+CyuXTzVkJrzWhS62kVOlaq6MgG7+XIDBl4g"/>
</map>
EOFPREFS
        chmod 600 "$prefs_file"
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
    for sock in /tmp/.X11-unix/X*; do
        if [ -S "\$sock" ] || [ -e "\$sock" ]; then
            disp_num="\${sock##*/X}"
            if [[ "\$disp_num" =~ ^[0-9]+$ ]]; then
                export DISPLAY=":\${disp_num}"
                break
            fi
        fi
    done
    if [ -z "\${DISPLAY:-}" ] && [ -n "\${WAYLAND_DISPLAY:-}" ]; then
        export DISPLAY=:0
    fi
fi

REPO_DIR="$REPO_DIR"
JAR_NAME="$jar_name"
BURP_VERSION="$burp_ver"

# Locate best Java 21+ binary
JAVA_BIN="java"
for j in \
    "/usr/lib/jvm/java-21-openjdk/bin/java" \
    "/usr/lib/jvm/java-21-openjdk-amd64/bin/java" \
    "/usr/lib/jvm/jre-21-openjdk/bin/java" \
    "/usr/lib/jvm/java-21/bin/java" \
    "/usr/lib/jvm/default-runtime/bin/java"; do
    if [ -x "\$j" ]; then
        JAVA_BIN="\$j"
        break
    fi
done

case "\${1:-}" in
    -k|--keygen)
        echo "Starting Burp Suite Keygen / Loader..."
        exec "\$JAVA_BIN" -jar "\$REPO_DIR/loader.jar"
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

Environment Variables:
  BURP_MAX_RAM    Maximum Java heap memory (e.g. BURP_MAX_RAM=8g burpsuitepro)
                  (Also respects BURP_MEMORY or BURP_RAM; defaults to 50% RAM)

All other arguments are passed directly to Burp Suite.
HLP
        exit 0
        ;;
esac

# Resolve file arguments to absolute paths before changing directory to REPO_DIR
BURP_ARGS=()
for arg in "\$@"; do
    if [ -e "\$arg" ]; then
        BURP_ARGS+=("\$(realpath "\$arg" 2>/dev/null || readlink -f "\$arg" 2>/dev/null || echo "\$arg")")
    else
        BURP_ARGS+=("\$arg")
    fi
done

# Dynamic memory sizing
MEM_OPTS=("-XX:MaxRAMPercentage=50")
BURP_MEM_VAL="\${BURP_MAX_RAM:-\${BURP_MEMORY:-\${BURP_RAM:-}}}"
if [ -n "\$BURP_MEM_VAL" ]; then
    if [[ "\$BURP_MEM_VAL" =~ ^-Xmx ]]; then
        MEM_OPTS=("\$BURP_MEM_VAL")
    else
        MEM_OPTS=("-Xmx\$BURP_MEM_VAL")
    fi
fi

# Generational ZGC Garbage Collector with G1GC fallback
GC_OPTS=("-XX:+UseG1GC")
if "\$JAVA_BIN" -XX:+UseZGC -XX:+ZGenerational -version >/dev/null 2>&1; then
    GC_OPTS=("-XX:+UseZGC" "-XX:+ZGenerational")
fi

# Port 8080 conflict detection
if ss -tlnH 'sport = :8080' 2>/dev/null | grep -q '8080'; then
    if [ -t 1 ]; then
        echo "[!] Warning: Port 8080 is already in use by another process." >&2
        echo "    Burp Suite default proxy listener may conflict. Close the conflicting app or reconfigure listeners." >&2
    elif command -v notify-send &>/dev/null; then
        notify-send -u normal -i burpsuitepro "Burp Suite Port Conflict" "Port 8080 is already in use. Burp's default proxy listener may fail to bind." 2>/dev/null || true
    fi
fi

cd "\$REPO_DIR"

JAVA_OPTS=(
    --add-opens=java.desktop/javax.swing=ALL-UNNAMED
    --add-opens=java.base/java.lang=ALL-UNNAMED
    --add-opens=java.base/java.util=ALL-UNNAMED
    --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED
    --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED
    --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED
    "\${MEM_OPTS[@]}"
    "\${GC_OPTS[@]}"
    -Dawt.useSystemAAFontSettings=on
    -Dswing.aatext=true
    -Dsun.java2d.uiScale=auto
    -Dawt.toolkit=sun.awt.X11.XToolkit
    -javaagent:"\$REPO_DIR/loader.jar"
    -jar "\$REPO_DIR/\$JAR_NAME"
)

if [ -t 1 ]; then
    exec "\$JAVA_BIN" "\${JAVA_OPTS[@]}" "\${BURP_ARGS[@]}"
else
    LOG_FILE="/tmp/burpsuitepro-\${UID:-\$USER}.log"
    "\$JAVA_BIN" "\${JAVA_OPTS[@]}" "\${BURP_ARGS[@]}" 2>"\$LOG_FILE"
    EXIT_CODE=\$?
    if [ \$EXIT_CODE -ne 0 ]; then
        ERR_MSG=\$(tail -n 10 "\$LOG_FILE" 2>/dev/null)
        [ -z "\$ERR_MSG" ] && ERR_MSG="Process exited with status \$EXIT_CODE. See \$LOG_FILE for details."
        NOTIFY_BODY=\$(printf "Burp Suite exited with code %s:\n%s" "\$EXIT_CODE" "\$ERR_MSG")
        if command -v notify-send &>/dev/null; then
            notify-send -u critical -i burpsuitepro "Burp Suite Error" "\$NOTIFY_BODY" 2>/dev/null || true
        elif command -v kdialog &>/dev/null; then
            kdialog --error "\$NOTIFY_BODY" 2>/dev/null || true
        fi
        exit \$EXIT_CODE
    fi
fi
EOF
    chmod +x "$launcher_path"

    if [[ -w /usr/local/bin ]]; then
        ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || true
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -n ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || true
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
Exec=$launcher_path %F
Icon=burpsuitepro
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=burp-StartBurp
MimeType=application/x-burp-project;
Categories=Network;Security;Development;WebDevelopment;03-web-application-analysis;03-05-web-vulnerability-scanners;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
Actions=Keygen;TrustCA;

[Desktop Action Keygen]
Name=Burp Suite Pro Keygen / Loader
Exec=$launcher_path -k
Icon=burpsuitepro

[Desktop Action TrustCA]
Name=Trust Burp CA Certificate
Exec=$launcher_path --trust-ca
Icon=burpsuitepro
EOF

    update-desktop-database "$desktop_dir" 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || kbuildsycoca6 2>/dev/null || kbuildsycoca5 2>/dev/null || true

    # System desktop shortcut if writable or passwordless sudo
    local sys_desktop_dir="/usr/local/share/applications"
    if [[ -w "$sys_desktop_dir" ]]; then
        cp -f "$desktop_file" "$sys_desktop_dir/burpsuitepro.desktop" 2>/dev/null || true
        update-desktop-database "$sys_desktop_dir" 2>/dev/null || true
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -n mkdir -p "$sys_desktop_dir" 2>/dev/null || true
        sudo -n cp -f "$desktop_file" "$sys_desktop_dir/burpsuitepro.desktop" 2>/dev/null || true
        sudo -n update-desktop-database "$sys_desktop_dir" 2>/dev/null || true
    fi

    # 8. Start Key Loader & Burp Suite Pro if not skipped
    if [[ "$skip_launch" == false ]]; then
        if [ -z "${DISPLAY:-}" ]; then
            for sock in /tmp/.X11-unix/X*; do
                if [ -S "$sock" ] || [ -e "$sock" ]; then
                    disp_num="${sock##*/X}"
                    if [[ "$disp_num" =~ ^[0-9]+$ ]]; then
                        export DISPLAY=":${disp_num}"
                        break
                    fi
                fi
            done
            if [ -z "${DISPLAY:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
                export DISPLAY=:0
            fi
        fi

        local active_java
        active_java="$(find_java_bin)"

        if [ -f "$REPO_DIR/loader.jar" ]; then
            echo "Starting Key loader.jar in background..."
            nohup "$active_java" -jar "$REPO_DIR/loader.jar" >/dev/null 2>&1 &
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
            echo "Waiting for Burp Suite proxy listener (up to 5 min / 300s)..."
            for ((att = 1; att <= 60; att++)); do
                sleep 5
                if curl -s -f -m 3 "$cert_url" -o /dev/null 2>/dev/null; then
                    cert_active=true
                    break
                fi
                echo "  Waiting for proxy listener... ($((att * 5))/300s)"
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
