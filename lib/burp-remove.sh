#!/usr/bin/env bash
# ============================================================================
# Burp Suite Professional Universal Uninstaller
# ============================================================================

set -euo pipefail

# Source common definitions (Fix 1)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/burp-common.sh" ]]; then
    # shellcheck source=lib/burp-common.sh
    source "$SCRIPT_DIR/burp-common.sh"
fi

REPO_DIR="${REPO_DIR:-$HOME/Documents/Crack/Burpsuite-Professional}"
LAUNCHER_PATH="$HOME/.local/bin/burpsuitepro"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/burpsuitepro.desktop"

PURGE=false
DELETE_DATA=false
KEEP_DATA=false
UNTRUST_CA=false
MODE_UNTRUST_CA_ONLY=false
ASSUME_YES=false
FORCE=false

show_help() {
    cat <<EOF
Burp Suite Professional Universal Uninstaller

Usage: $(basename "$0") [OPTIONS]

Options:
  --keep-data          Explicitly keep user preferences and projects (default)
  --purge              Completely delete user preferences (~/.BurpSuite,
                       ~/.java/.userPrefs/burp), REPO_DIR, and PortSwigger CA
  --delete-data        Delete user preferences and project data
  --untrust-ca         Remove PortSwigger CA certificates from system trust store,
                       browser profiles, and enterprise policies
  --untrust-ca-only    Only untrust CA certificates without uninstalling Burp
  -y, --yes            Non-interactive mode, skip confirmation prompts
  -f, --force          Force removal without prompting
  -h, --help           Show this help message

EOF
}

# 1. Parse CLI arguments (Fix G4: while loop allows arguments in any position)
while [[ $# -gt 0 ]]; do
    case "$1" in
    --purge)
        PURGE=true
        shift
        ;;
    --delete-data)
        DELETE_DATA=true
        shift
        ;;
    --keep-data)
        KEEP_DATA=true
        shift
        ;;
    --untrust-ca)
        UNTRUST_CA=true
        shift
        ;;
    --untrust-ca-only)
        UNTRUST_CA=true
        MODE_UNTRUST_CA_ONLY=true
        shift
        ;;
    -y | --yes)
        ASSUME_YES=true
        shift
        ;;
    -f | --force)
        FORCE=true
        ASSUME_YES=true
        shift
        ;;
    -h | --help)
        show_help
        exit 0
        ;;
    *)
        echo "ERROR: Unknown option: $1" >&2
        show_help
        exit 1
        ;;
    esac
done

# If --untrust-ca was passed without uninstall actions, enter standalone untrust mode (Fix A2)
if [[ "$UNTRUST_CA" = true ]] && [[ "$PURGE" = false ]] && [[ "$DELETE_DATA" = false ]] && [[ "$KEEP_DATA" = false ]]; then
    MODE_UNTRUST_CA_ONLY=true
fi

# Privilege helpers
can_passwordless_root() {
    [[ $EUID -eq 0 ]] || (command -v sudo &>/dev/null && sudo -n true 2>/dev/null)
}

run_passwordless_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -n "$@"
    else
        return 1
    fi
}

as_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        if [[ "$ASSUME_YES" = true ]] || [ ! -t 0 ]; then
            if sudo -n true 2>/dev/null; then
                sudo -n "$@"
            else
                return 1
            fi
        else
            sudo "$@"
        fi
    else
        return 1
    fi
}

remove_user_file() {
    local target="$1"
    local desc="${2:-user file}"
    if [[ -e "$target" || -L "$target" ]]; then
        if rm -f "$target" 2>/dev/null; then
            echo "  [✓] Removed $desc: $target"
        fi
    fi
}

remove_system_file() {
    local target="$1"
    local desc="${2:-system file}"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -w "$target" || -w "$(dirname "$target")" ]]; then
            if rm -f "$target" 2>/dev/null; then
                echo "  [✓] Removed $desc: $target"
                return 0
            fi
        elif [[ $EUID -eq 0 ]]; then
            if rm -f "$target" 2>/dev/null; then
                echo "  [✓] Removed $desc: $target"
                return 0
            fi
        elif as_sudo rm -f "$target" 2>/dev/null; then
            echo "  [✓] Removed $desc (via sudo): $target"
            return 0
        else
            echo "  [-] Skipped $desc: $target (insufficient permissions, sudo unavailable)"
            return 1
        fi
    fi
    return 0
}

# Clean system launcher symlink cleanly, verifying it points to burpsuitepro (Fix E5)
clean_system_launcher_symlink() {
    local target="/usr/local/bin/burpsuitepro"
    if [[ -L "$target" ]]; then
        local link_dest
        link_dest="$(readlink "$target" 2>/dev/null || true)"
        if [[ "$link_dest" == *"burpsuitepro"* || "$link_dest" == *"$REPO_DIR"* || "$link_dest" == *"Burpsuite"* ]]; then
            remove_system_file "$target" "system binary symlink (-> $link_dest)"
        else
            echo "  [-] Preserved $target: symlink points to non-Burp target ($link_dest)"
        fi
    elif [[ -f "$target" ]]; then
        if grep -qi "burpsuite" "$target" 2>/dev/null; then
            remove_system_file "$target" "system binary launcher"
        else
            echo "  [-] Preserved $target: file does not match Burp Suite"
        fi
    fi
}

# Check if REPO_DIR contains user-added files or extensions (Fix G3)
has_custom_repo_files() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return 1
    local custom_found=false
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local bname
        bname="$(basename "$f")"
        case "$bname" in
        burpsuite_pro_v*.jar | *.jar.bk | loader.jar | jython-standalone-*.jar | jruby-complete-*.jar | .config.ini | burp_suite_pro_icon.svg | burp-trust-ca.sh | burp-common.sh | burpsuitepro)
            ;;
        *)
            custom_found=true
            break
            ;;
        esac
    done < <(find "$dir" -maxdepth 1 -mindepth 1 2>/dev/null)
    [[ "$custom_found" = true ]]
}

# 7. Untrust CA certificates functions (Fix A2)
untrust_system_ca() {
    echo "Removing PortSwigger CA from system trust store..."
    local found_any=false

    # Arch Linux (/etc/ca-certificates/trust-source/anchors/burpsuite-ca.crt)
    local arch_anchor="/etc/ca-certificates/trust-source/anchors/burpsuite-ca.crt"
    if [[ -f "$arch_anchor" ]]; then
        found_any=true
        if as_sudo rm -f "$arch_anchor"; then
            if command -v trust &>/dev/null; then
                as_sudo trust extract-compat 2>/dev/null || true
            fi
            echo "  [✓] Removed $arch_anchor (Arch trust store updated via trust extract-compat)."
        else
            echo "  [-] Skipped $arch_anchor (insufficient permissions, sudo unavailable)"
        fi
    fi

    # Debian / Kali / Ubuntu (/usr/local/share/ca-certificates/burpsuite-ca.crt)
    local deb_anchor="/usr/local/share/ca-certificates/burpsuite-ca.crt"
    if [[ -f "$deb_anchor" ]]; then
        found_any=true
        if as_sudo rm -f "$deb_anchor"; then
            if command -v update-ca-certificates &>/dev/null; then
                as_sudo update-ca-certificates --fresh 2>/dev/null || as_sudo update-ca-certificates 2>/dev/null || true
            fi
            echo "  [✓] Removed $deb_anchor (Debian/Kali trust store updated via update-ca-certificates)."
        else
            echo "  [-] Skipped $deb_anchor (insufficient permissions, sudo unavailable)"
        fi
    fi

    # Fedora / RHEL (/etc/pki/ca-trust/source/anchors/burpsuite-ca.crt)
    local rhel_anchor="/etc/pki/ca-trust/source/anchors/burpsuite-ca.crt"
    if [[ -f "$rhel_anchor" ]]; then
        found_any=true
        if as_sudo rm -f "$rhel_anchor"; then
            if command -v update-ca-trust &>/dev/null; then
                as_sudo update-ca-trust 2>/dev/null || true
            fi
            echo "  [✓] Removed $rhel_anchor (Fedora trust store updated via update-ca-trust)."
        else
            echo "  [-] Skipped $rhel_anchor (insufficient permissions, sudo unavailable)"
        fi
    fi

    if [[ "$found_any" = false ]]; then
        echo "  [-] No PortSwigger CA certificate found in standard system trust anchors."
    fi
}

untrust_browser_profiles() {
    if ! command -v certutil &>/dev/null; then
        echo "Note: certutil (nss / libnss3-tools) is not installed. Skipping direct profile untrust."
        return 0
    fi

    echo "Searching for browser profiles and NSS databases to untrust PortSwigger CA..."
    local search_dirs=(
        "$HOME/.pki/nssdb"
        "$HOME/.mozilla"
        "$HOME/.config/mozilla"
        "$HOME/.zen"
        "$HOME/.config/zen"
        "$HOME/.librewolf"
        "$HOME/.config/librewolf"
        "$HOME/.floorp"
        "$HOME/.config/floorp"
        "$HOME/.waterfox"
        "$HOME/.config/waterfox"
        "$HOME/snap/firefox/common/.mozilla/firefox"
        "$HOME/snap/chromium/current/.pki/nssdb"
        "$HOME/.var/app/org.mozilla.firefox"
        "$HOME/.var/app/io.github.zen_browser.zen"
        "$HOME/.var/app/app.zen_browser.zen"
        "$HOME/.var/app/io.gitlab.librewolf-community"
        "$HOME/.var/app/one.ablaze.floorp"
        "$HOME/.var/app/net.waterfox.waterfox"
        "$HOME/.var/app/org.chromium.Chromium"
        "$HOME/.var/app/com.google.Chrome"
        "$HOME/.var/app/com.brave.Browser"
        "$HOME/.var/app/com.microsoft.Edge"
    )

    local target_dirs=()
    for d in "${search_dirs[@]}"; do
        [[ -d "$d" ]] && target_dirs+=("$d")
    done

    # Flatpak user data directories
    if [[ -d "$HOME/.var/app" ]]; then
        for d in "$HOME/.var/app"/*; do
            if [[ -d "$d" ]]; then
                local already=false
                for t in "${target_dirs[@]}"; do
                    if [[ "$t" == "$d" ]]; then
                        already=true
                        break
                    fi
                done
                [[ "$already" = false ]] && target_dirs+=("$d")
            fi
        done
    fi

    if [[ ${#target_dirs[@]} -eq 0 ]]; then
        echo "  [-] No browser profile directories or NSS databases found."
        return 0
    fi

    # Deduplicate profile database directories
    local profile_dirs=()
    while IFS= read -r db; do
        [[ -z "$db" ]] && continue
        local p
        p="$(dirname "$db")"
        local seen=false
        for exist_p in "${profile_dirs[@]}"; do
            if [[ "$exist_p" == "$p" ]]; then
                seen=true
                break
            fi
        done
        [[ "$seen" = false ]] && profile_dirs+=("$p")
    done < <(find "${target_dirs[@]}" \( -name "cert9.db" -o -name "cert8.db" \) 2>/dev/null)

    if [[ ${#profile_dirs[@]} -eq 0 ]]; then
        echo "  [-] No cert9.db or cert8.db databases found."
        return 0
    fi

    # Check for running browsers that could lock databases
    local running_browsers=()
    for b_proc in firefox firefox-esr firefox-bin librewolf librewolf-bin floorp floorp-bin waterfox waterfox-bin zen zen-bin chrome chromium brave edge; do
        if pgrep -x "$b_proc" >/dev/null 2>&1 || pgrep -f "(^|/)$b_proc(\s|$)" >/dev/null 2>&1; then
            running_browsers+=("$b_proc")
        fi
    done
    if [ ${#running_browsers[@]} -gt 0 ]; then
        echo "  [!] Warning: Detected running browser process(es): ${running_browsers[*]}"
        echo "      Open browsers may lock NSS databases and prevent certificate removal."
    fi

    local found_any=false
    for p in "${profile_dirs[@]}"; do
        local removed_here=false
        # SQLite database (cert9.db)
        if [ -f "$p/cert9.db" ]; then
            if certutil -L -d "sql:$p" -n "PortSwigger CA" &>/dev/null; then
                if certutil -D -n "PortSwigger CA" -d "sql:$p" 2>/dev/null; then
                    echo "  [✓] Removed 'PortSwigger CA' from: $p (sql)"
                    removed_here=true
                else
                    echo "  [✗] Failed to remove 'PortSwigger CA' from: $p (sql, database may be locked)"
                fi
            elif certutil -D -n "PortSwigger CA" -d "sql:$p" 2>/dev/null; then
                echo "  [✓] Removed 'PortSwigger CA' from: $p (sql)"
                removed_here=true
            fi
        fi

        # Legacy DBM database (cert8.db)
        if [ -f "$p/cert8.db" ]; then
            if certutil -L -d "dbm:$p" -n "PortSwigger CA" &>/dev/null; then
                if certutil -D -n "PortSwigger CA" -d "dbm:$p" 2>/dev/null; then
                    echo "  [✓] Removed 'PortSwigger CA' from: $p (dbm)"
                    removed_here=true
                else
                    echo "  [✗] Failed to remove 'PortSwigger CA' from: $p (dbm, database may be locked)"
                fi
            elif certutil -D -n "PortSwigger CA" -d "dbm:$p" 2>/dev/null; then
                echo "  [✓] Removed 'PortSwigger CA' from: $p (dbm)"
                removed_here=true
            fi
        fi

        if [[ "$removed_here" = true ]]; then
            found_any=true
        fi
    done

    if [[ "$found_any" = false ]]; then
        echo "  [-] No PortSwigger CA certificates found in detected browser NSS databases."
    fi
}

untrust_enterprise_roots() {
    echo "Checking browser Enterprise Roots policies..."
    for b in firefox firefox-esr librewolf floorp waterfox zen; do
        local pdir="/etc/$b/policies"
        local pfile="$pdir/policies.json"
        local pbak="$pdir/policies.json.bak"

        if [[ -f "$pbak" ]]; then
            if as_sudo mv -f "$pbak" "$pfile" 2>/dev/null; then
                echo "  [✓] Restored $pfile from backup ($pbak)"
            else
                echo "  [-] Skipped restoring $pfile from $pbak (insufficient permissions)"
            fi
        elif [[ -f "$pfile" ]]; then
            if command -v python3 &>/dev/null; then
                local tmp_out
                tmp_out="$(mktemp "${TMPDIR:-/tmp}/burp-pol-rm-XXXXXX.json" 2>/dev/null || mktemp /tmp/burp-pol-rm-XXXXXX.json)"
                local py_res=0
                python3 -c "
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, 'r', encoding='utf-8') as f:
        d = json.load(f)
except Exception:
    sys.exit(1)

if not isinstance(d, dict):
    sys.exit(1)

p = d.get('policies')
if not isinstance(p, dict):
    sys.exit(0)

if 'ImportEnterpriseRoots' not in p:
    sys.exit(0)

del p['ImportEnterpriseRoots']

if not p and len(d) == 1:
    sys.exit(2)

with open(dst, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
sys.exit(3)
" "$pfile" "$tmp_out" 2>/dev/null || py_res=$?

                if [[ "$py_res" -eq 2 ]]; then
                    if as_sudo rm -f "$pfile" 2>/dev/null; then
                        echo "  [✓] Removed $pfile (contained only Burp EnterpriseRoots policy)"
                        as_sudo rmdir "$pdir" 2>/dev/null || true
                    else
                        echo "  [-] Skipped removing $pfile (insufficient permissions)"
                    fi
                elif [[ "$py_res" -eq 3 ]]; then
                    if as_sudo cp -f "$tmp_out" "$pfile" 2>/dev/null; then
                        as_sudo chmod 644 "$pfile" 2>/dev/null || true
                        echo "  [✓] Removed ImportEnterpriseRoots from $pfile"
                    else
                        echo "  [-] Skipped updating $pfile (insufficient permissions)"
                    fi
                fi
                rm -f "$tmp_out"
            else
                if grep -q "ImportEnterpriseRoots" "$pfile" 2>/dev/null; then
                    local stripped
                    stripped=$(grep -vE '^\s*("policies"|\{|\}|"ImportEnterpriseRoots")' "$pfile" | tr -d '[:space:]')
                    if [[ -z "$stripped" ]]; then
                        if as_sudo rm -f "$pfile" 2>/dev/null; then
                            echo "  [✓] Removed $pfile"
                            as_sudo rmdir "$pdir" 2>/dev/null || true
                        else
                            echo "  [-] Skipped removing $pfile (insufficient permissions)"
                        fi
                    else
                        if as_sudo sed -i '/ImportEnterpriseRoots/d' "$pfile" 2>/dev/null; then
                            echo "  [✓] Cleaned ImportEnterpriseRoots from $pfile"
                        else
                            echo "  [-] Skipped cleaning $pfile (insufficient permissions)"
                        fi
                    fi
                fi
            fi
        fi
    done
}

untrust_ca() {
    echo "=== Untrusting PortSwigger CA Certificate ==="
    untrust_system_ca
    untrust_browser_profiles
    untrust_enterprise_roots
    echo "[✓] PortSwigger CA untrust process completed."
}

# Standalone untrust invocation (Fix A2: ./lib/burp-remove.sh --untrust-ca)
if [[ "$MODE_UNTRUST_CA_ONLY" = true ]]; then
    untrust_ca
    exit 0
fi

echo "=== Burp Suite Professional Universal Uninstaller ==="

# Determine user data deletion behavior (Fix G1)
DELETE_USER_DATA=false
if [[ "$KEEP_DATA" = true ]]; then
    DELETE_USER_DATA=false
elif [[ "$PURGE" = true ]] || [[ "$DELETE_DATA" = true ]]; then
    DELETE_USER_DATA=true
else
    # Default is keep-data. If run interactively without --purge/--delete-data, prompt with default 'N'
    if [[ "$ASSUME_YES" = false ]] && [ -t 0 ]; then
        read -r -p "Do you want to delete user preferences and project data (~/.BurpSuite, ~/.java/.userPrefs/burp)? [y/N]: " reply_data || true
        if [[ "$reply_data" =~ ^[Yy]$ ]]; then
            DELETE_USER_DATA=true
        else
            DELETE_USER_DATA=false
        fi
    else
        DELETE_USER_DATA=false
    fi
fi

# Determine PortSwigger CA untrusting behavior
SHOULD_UNTRUST_CA=false
if [[ "$UNTRUST_CA" = true ]] || [[ "$PURGE" = true ]]; then
    SHOULD_UNTRUST_CA=true
elif [[ "$ASSUME_YES" = false ]] && [ -t 0 ]; then
    read -r -p "Do you want to untrust and remove PortSwigger CA certificates from system store and browsers? [y/N]: " reply_ca || true
    if [[ "$reply_ca" =~ ^[Yy]$ ]]; then
        SHOULD_UNTRUST_CA=true
    fi
fi

# 2. Stop running processes (Fix G2: targeted process kill)
echo "Stopping any running Burp Suite processes..."
pkill -f '(java|openjdk).*[b]urpsuite_pro_v.*\.jar' 2>/dev/null || true
pkill -f '(^|/)[b]urpsuitepro(\s|$)' 2>/dev/null || true

# 3. Remove desktop shortcuts, icons, MIME definitions & binaries
echo "Removing desktop entries, icons, MIME definitions, and binaries..."
remove_user_file "$DESKTOP_FILE" "user desktop shortcut"
remove_user_file "$LAUNCHER_PATH" "user launcher"

# Remove user-level icons
remove_user_file "$HOME/.local/share/icons/hicolor/scalable/apps/burpsuitepro.svg" "user scalable icon"
for icon in "$HOME/.local/share/icons/hicolor"/*/apps/burpsuitepro.png; do
    if [[ -e "$icon" || -L "$icon" ]]; then
        remove_user_file "$icon" "user icon"
    fi
done
remove_user_file "$HOME/.local/share/pixmaps/burpsuitepro.svg" "user pixmap icon"
remove_user_file "$HOME/.local/share/pixmaps/burpsuitepro.png" "user pixmap icon"

# Remove user-level MIME definition
remove_user_file "$HOME/.local/share/mime/packages/burpsuitepro.xml" "user MIME definition"

# Clean system launcher symlink (Fix E5)
clean_system_launcher_symlink

# Attempt cleanup in system paths only if running as root or passwordless sudo succeeds
remove_system_file "/usr/local/share/applications/burpsuitepro.desktop" "system desktop shortcut"
remove_system_file "/usr/local/share/icons/hicolor/scalable/apps/burpsuitepro.svg" "system scalable icon"
for icon in /usr/local/share/icons/hicolor/*/apps/burpsuitepro.png; do
    if [[ -e "$icon" || -L "$icon" ]]; then
        remove_system_file "$icon" "system icon"
    fi
done
remove_system_file "/usr/share/pixmaps/burpsuitepro.svg" "system pixmap icon"
remove_system_file "/usr/share/pixmaps/burpsuitepro.png" "system pixmap icon"
remove_system_file "/usr/local/share/mime/packages/burpsuitepro.xml" "system MIME definition"

# 4. Remove installation directory (Fix G3: ask/verify before removing REPO_DIR)
if [[ -d "$REPO_DIR" ]]; then
    custom_files=false
    if has_custom_repo_files "$REPO_DIR"; then
        custom_files=true
    fi

    do_wipe_repo=false
    if [[ "$FORCE" = true ]]; then
        do_wipe_repo=true
    elif [[ "$PURGE" = true ]]; then
        if [[ "$custom_files" = true ]]; then
            if [[ "$ASSUME_YES" = false ]] && [ -t 0 ]; then
                read -r -p "Installation directory $REPO_DIR contains custom user files/extensions. Delete entire directory? [y/N]: " reply_repo || true
                if [[ "$reply_repo" =~ ^[Yy]$ ]]; then
                    do_wipe_repo=true
                else
                    do_wipe_repo=false
                fi
            else
                echo "  [*] Detected custom files/extensions in $REPO_DIR; preserving them (use --force to override)."
                do_wipe_repo=false
            fi
        else
            do_wipe_repo=true
        fi
    fi

    if [[ "$do_wipe_repo" = true ]]; then
        echo "Removing installation folder completely: $REPO_DIR"
        rm -rf "$REPO_DIR"
        echo "  [✓] Removed installation folder: $REPO_DIR"
    else
        echo "Safely removing installed Burp Suite files from $REPO_DIR..."
        (
            shopt -s nullglob
            for f in "$REPO_DIR"/burpsuite_pro_v*.jar \
                "$REPO_DIR"/*.jar.bk \
                "$REPO_DIR"/loader.jar \
                "$REPO_DIR"/jython-standalone-*.jar \
                "$REPO_DIR"/jruby-complete-*.jar \
                "$REPO_DIR"/.config.ini \
                "$REPO_DIR"/burp_suite_pro_icon.svg \
                "$REPO_DIR"/burp-trust-ca.sh \
                "$REPO_DIR"/burp-common.sh \
                "$REPO_DIR"/burpsuitepro; do
                if [[ -e "$f" || -L "$f" ]]; then
                    rm -f "$f"
                    echo "  [✓] Removed installed file: $f"
                fi
            done
        )
        if [[ -d "$REPO_DIR" ]] && [[ -z "$(ls -A "$REPO_DIR" 2>/dev/null)" ]]; then
            rmdir "$REPO_DIR" 2>/dev/null || true
            echo "  [✓] Removed empty installation folder: $REPO_DIR"
        elif [[ -d "$REPO_DIR" ]]; then
            echo "  [*] Preserved custom user files and extensions in $REPO_DIR"
        fi
    fi
fi

# Clean parent directory if empty
PARENT_DIR="$(dirname "$REPO_DIR")"
if [[ -d "$PARENT_DIR" ]] && [[ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]]; then
    rmdir "$PARENT_DIR" 2>/dev/null || true
    echo "  [✓] Removed empty parent directory: $PARENT_DIR"
fi

# 5. Clean user preferences and caches (Fix G1)
if [[ "$DELETE_USER_DATA" = true ]]; then
    echo "Cleaning user data and caches..."
    rm -rf "$HOME/.BurpSuite"
    rm -rf "$HOME/.java/.userPrefs/burp"
    rm -rf "$HOME/.java/.userPrefs/BurpSuite"
    echo "  [✓] Removed user preferences and caches."
else
    echo "Preserving user preferences and project data (~/.BurpSuite)."
fi

# 6. Cleanup temporary logs (Fix G5)
echo "Cleaning temporary logs..."
rm -f "/tmp/burpsuitepro-${UID:-$USER}.log" 2>/dev/null || true
rm -f "/tmp/burpsuitepro-${UID}.log" "/tmp/burpsuitepro-${USER}.log" 2>/dev/null || true
rm -f /tmp/burpsuitepro-*.log 2>/dev/null || true
rm -f "${TMPDIR:-/tmp}"/burp-ca-*.tmp "${TMPDIR:-/tmp}"/burp-ca-*.der "${TMPDIR:-/tmp}"/burp-ca-*.crt 2>/dev/null || true
rm -f "${TMPDIR:-/tmp}"/burp-pol-*.json "${TMPDIR:-/tmp}"/burp-pol-err-*.tmp 2>/dev/null || true
rm -f "${TMPDIR:-/tmp}"/burp-cert-check-*.tmp 2>/dev/null || true
echo "  [✓] Cleaned temporary logs."

# 7. Untrust CA certificates (Fix A2: executed during full uninstall if selected)
if [[ "$SHOULD_UNTRUST_CA" = true ]]; then
    untrust_ca
fi

# 8. Regenerate desktop, icon, and MIME caches
echo "Regenerating desktop, icon, and MIME caches..."
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi
if command -v update-mime-database &>/dev/null; then
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
fi
if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental 2>/dev/null || kbuildsycoca6 2>/dev/null || true
elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 2>/dev/null || true
fi

# System cache updates if writable or passwordless sudo
if [[ -w /usr/local/share/applications ]]; then
    update-desktop-database /usr/local/share/applications 2>/dev/null || true
elif can_passwordless_root; then
    run_passwordless_root update-desktop-database /usr/local/share/applications 2>/dev/null || true
fi

if [[ -w /usr/local/share/icons/hicolor ]]; then
    gtk-update-icon-cache -f -q -t /usr/local/share/icons/hicolor 2>/dev/null || true
elif can_passwordless_root; then
    run_passwordless_root gtk-update-icon-cache -f -q -t /usr/local/share/icons/hicolor 2>/dev/null || true
fi

if [[ -w /usr/local/share/mime ]]; then
    update-mime-database /usr/local/share/mime 2>/dev/null || true
elif can_passwordless_root; then
    run_passwordless_root update-mime-database /usr/local/share/mime 2>/dev/null || true
fi

echo "=== Burp Suite Professional removal complete! ==="
