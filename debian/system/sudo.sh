#!/usr/bin/env bash
# ============================================================================
# DEBIAN SUDO SETUP & USER CONFIGURATION
# Grants full sudo privileges to the specified user on fresh Debian systems.
# Handles auto-elevation via 'su' if sudo is not yet installed or configured.
# ============================================================================

set -euo pipefail

# Formatting colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[*]${NC} $*"; }
log_success() { echo -e "${GREEN}[✔]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✘]${NC} $*"; }

# ----------------------------------------------------------------------------
# 1. Elevation check: if not root, escalate using 'su'
# ----------------------------------------------------------------------------
CURRENT_UID="$(id -u)"
CALLING_USER="${1:-${SUDO_USER:-$(logname 2>/dev/null || id -un)}}"

if [ "$CURRENT_UID" -ne 0 ]; then
    # Test if current user already has sudo working
    if command -v sudo >/dev/null 2>&1 && sudo -v 2>/dev/null; then
        exec sudo bash "$0" "$CALLING_USER"
    fi

    echo -e "${YELLOW}${BOLD}Debian root authentication required${NC}"
    echo "Sudo is not yet configured for user: ${BOLD}${CALLING_USER}${NC}"
    echo "Please enter the ${BOLD}root${NC} password to elevate and configure sudo:"
    echo ""

    SCRIPT_PATH="$(readlink -f "$0")"
    exec su - -c "bash '$SCRIPT_PATH' '$CALLING_USER'"
fi

# ----------------------------------------------------------------------------
# 2. Determine target user (running as root from here)
# ----------------------------------------------------------------------------
TARGET_USER="${1:-${SUDO_USER:-}}"

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    # Try finding the first non-system user (UID >= 1000)
    DETECTED_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || true)"
    if [ -n "$DETECTED_USER" ]; then
        TARGET_USER="$DETECTED_USER"
    else
        read -rp "Enter username to add to sudo group: " TARGET_USER
    fi
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    log_error "User '$TARGET_USER' does not exist."
    exit 1
fi

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BOLD}Configuring Sudo Privileges for: ${GREEN}${TARGET_USER}${NC}"
echo -e "${BLUE}=====================================================${NC}"

# ----------------------------------------------------------------------------
# 3. Ensure standard sbin paths exist in environment
# ----------------------------------------------------------------------------
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

# Fix Debian's missing /sbin and /usr/sbin for regular users
PATH_FIX_FILE="/etc/profile.d/00-default-paths.sh"
if [ ! -f "$PATH_FIX_FILE" ]; then
    log_info "Ensuring /usr/sbin and /sbin are in default system PATH..."
    cat << 'EOF' > "$PATH_FIX_FILE"
# Ensure administrative binaries are in user PATH
case ":$PATH:" in
    *:/usr/local/sbin:*) ;;
    *) export PATH="/usr/local/sbin:$PATH" ;;
esac
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) export PATH="/usr/sbin:$PATH" ;;
esac
case ":$PATH:" in
    *:/sbin:*) ;;
    *) export PATH="/sbin:$PATH" ;;
esac
EOF
    chmod 644 "$PATH_FIX_FILE"
fi

# ----------------------------------------------------------------------------
# 4. Install sudo package if missing
# ----------------------------------------------------------------------------
if ! command -v sudo >/dev/null 2>&1; then
    log_info "Installing 'sudo' package via apt..."
    apt-get update -y
    apt-get install -y sudo
    log_success "'sudo' installed."
else
    log_info "'sudo' is already installed."
fi

# ----------------------------------------------------------------------------
# 5. Add user to sudo group
# ----------------------------------------------------------------------------
log_info "Adding '$TARGET_USER' to 'sudo' group..."
usermod -aG sudo "$TARGET_USER"
log_success "'$TARGET_USER' added to 'sudo' group."

# ----------------------------------------------------------------------------
# 6. Configure sudoers entry
# ----------------------------------------------------------------------------
SUDOERS_FILE="/etc/sudoers.d/99-${TARGET_USER}"
log_info "Setting up sudoers configuration in $SUDOERS_FILE..."

# Safe creation: standard sudo privileges for the target user
TMP_FILE="$(mktemp)"
cat << EOF > "$TMP_FILE"
# Sudo privileges for ${TARGET_USER} configured by post_install
${TARGET_USER} ALL=(ALL:ALL) ALL
EOF

chmod 440 "$TMP_FILE"

# Validate syntax using visudo before deploying
if visudo -cf "$TMP_FILE" >/dev/null 2>&1; then
    cp "$TMP_FILE" "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    rm -f "$TMP_FILE"
    log_success "Sudoers permissions configured and verified."
else
    rm -f "$TMP_FILE"
    log_error "Validation of sudoers configuration failed. Aborting sudoers file change."
    exit 1
fi

# ----------------------------------------------------------------------------
# 7. Verification and Next Steps
# ----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}${BOLD}✔ Sudo setup completed successfully!${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "User ${BOLD}${TARGET_USER}${NC} now has full sudo permissions."
echo ""
echo -e "${YELLOW}Important:${NC} Group changes take effect on your next login session."
echo -e "To use sudo ${BOLD}immediately${NC} in your current terminal without logging out, run:"
echo ""
echo -e "   ${BOLD}newgrp sudo${NC}"
echo -e "   or"
echo -e "   ${BOLD}su - ${TARGET_USER}${NC}"
echo ""
