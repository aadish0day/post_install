#!/usr/bin/env bash
# ==============================================================================
# Common definitions and functions for Burp Suite Professional scripts
# ==============================================================================

# Shared installation directory
REPO_DIR="${REPO_DIR:-$HOME/Documents/Crack/Burpsuite-Professional}"
DEFAULT_BURP_VER="2026.10.1"
DEFAULT_JAR_NAME="burpsuite_pro_v${DEFAULT_BURP_VER}.jar"

# Locate burpsuitepro launcher
find_burp_bin() {
    if [ -n "${BURP_BIN:-}" ] && [ "$BURP_BIN" != "none" ] && [ -x "$BURP_BIN" ]; then
        echo "$BURP_BIN"
        return 0
    fi
    local b
    for b in "$HOME/.local/bin/burpsuitepro" "/usr/local/bin/burpsuitepro" "$REPO_DIR/burpsuitepro"; do
        if [ -x "$b" ]; then
            echo "$b"
            return 0
        fi
    done
    if command -v burpsuitepro &>/dev/null; then
        command -v burpsuitepro
        return 0
    fi
    return 1
}

# Unified prefs.xml merger: merges key/value entries into Java preferences XML
# Arguments: $1 = path to prefs.xml, $2 = key name, $3 = value
merge_pref_entry() {
    local prefs_file="$1"
    local key="$2"
    local val="$3"

    if [[ ! -f "$prefs_file" || ! -s "$prefs_file" ]] || ! grep -q "</map>" "$prefs_file" 2>/dev/null; then
        mkdir -p "$(dirname "$prefs_file")"
        cat <<EOF >"$prefs_file"
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="$key" value="$val"/>
</map>
EOF
        chmod 600 "$prefs_file" 2>/dev/null || true
    else
        if grep -qF "key=\"$key\"" "$prefs_file"; then
            sed -i "s|<entry key=\"$key\" value=\".*\"/>|<entry key=\"$key\" value=\"$val\"/>|" "$prefs_file"
        else
            sed -i "/<\/map>/i \  <entry key=\"$key\" value=\"$val\"/>" "$prefs_file"
        fi
        chmod 600 "$prefs_file" 2>/dev/null || true
    fi
}
