#!/bin/bash
set -uo pipefail

# Kali Linux User Setup Script
# Creates a new user with pentesting permissions and removes the default kali user

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

echo "Kali Linux User Setup Script"
echo "============================="
echo

# Get new username
NEW_USER="${1:-}"
if [[ -z "$NEW_USER" ]]; then
    read -r -p "Enter the new username: " NEW_USER
fi

# Validate username
if [[ -z "$NEW_USER" ]]; then
    echo "Error: Username cannot be empty"
    exit 1
fi

if [[ "$NEW_USER" == "kali" ]]; then
    echo "Error: New username cannot be 'kali'"
    exit 1
fi

if id "$NEW_USER" &>/dev/null; then
    echo "Error: User $NEW_USER already exists"
    exit 1
fi

# Check if default kali user exists
if ! id "kali" &>/dev/null; then
    echo "Warning: Default 'kali' user not found"
    KALI_EXISTS=false
else
    KALI_EXISTS=true
fi

# Create the new user
echo "Creating user: $NEW_USER"
adduser --gecos "" "$NEW_USER"

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create user"
    exit 1
fi

# Add user to sudo group first (most important)
echo "Adding user to sudo group..."
usermod -aG sudo "$NEW_USER"

# Verify sudo group was added
if groups "$NEW_USER" | grep -q "\bsudo\b"; then
    echo "Successfully added to sudo group"
else
    echo "Warning: Failed to add to sudo group"
    exit 1
fi

# Add user to other required groups
echo "Adding user to additional groups..."
EXTRA_GROUPS="dialout wireshark bluetooth netdev kaboxer vboxsf docker"

for group in $EXTRA_GROUPS; do
    if getent group "$group" >/dev/null 2>&1; then
        usermod -aG "$group" "$NEW_USER"
    fi
done

# Set proper ownership
chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"

# Create common directories
su - "$NEW_USER" -c "mkdir -p ~/Documents ~/Downloads ~/cybersec ~/Scripts"

# Handle default kali user removal
if [[ "$KALI_EXISTS" == true ]]; then
    # True if kali is the invoking user OR has any login session (GUI, tty, ssh).
    # SUDO_USER/logname alone miss a GUI session when this script is run via `su -`.
    kali_session_active() {
        local u
        for u in "${SUDO_USER:-}" "$(logname 2>/dev/null || true)"; do
            [[ "$u" == "kali" ]] && return 0
        done
        if command -v loginctl >/dev/null 2>&1 &&
            loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -qx kali; then
            return 0
        fi
        who 2>/dev/null | awk '{print $1}' | grep -qx kali
    }

    if kali_session_active; then
        echo
        echo "Notice: Current active session belongs to 'kali'."
        echo "Skipping removal, renaming, usermod, or locking of the active 'kali' user account to prevent session self-termination."
        echo "Please log out, log in as '$NEW_USER', and remove or modify 'kali' from that session if desired."
    else
        echo
        read -r -p "Remove the default 'kali' user? (yes/no): " REMOVE_KALI

        if [[ "$REMOVE_KALI" == "yes" || "$REMOVE_KALI" == "y" ]]; then
            echo "Removing kali user..."
            pkill -u kali 2>/dev/null || true
            sleep 2
            if userdel kali; then
                # Keep the home directory (no -r): move it aside instead of destroying it.
                if [[ -d /home/kali ]]; then
                    BACKUP_HOME="/home/kali.removed.$(date +%s)"
                    mv /home/kali "$BACKUP_HOME"
                    echo "Old home kept at $BACKUP_HOME (delete it yourself once you have copied what you need)."
                fi
                rm -f /etc/sudoers.d/kali 2>/dev/null || true
                echo "Kali user removed"
            else
                echo "Warning: userdel kali failed; user not removed." >&2
            fi
        fi
    fi
fi

# Auto-login configuration (lightdm and gdm3 supported; sddm needs a session name, so it is skipped)
echo
read -r -p "Enable auto-login for $NEW_USER? (yes/no): " AUTO_LOGIN

if [[ "$AUTO_LOGIN" == "yes" || "$AUTO_LOGIN" == "y" ]]; then
    if command -v lightdm >/dev/null 2>&1 || [[ -d /etc/lightdm ]]; then
        # Drop-in instead of editing lightdm.conf; it overrides any existing autologin-user
        mkdir -p /etc/lightdm/lightdm.conf.d
        printf '[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$NEW_USER" >/etc/lightdm/lightdm.conf.d/50-autologin.conf
        echo "Auto-login enabled via /etc/lightdm/lightdm.conf.d/50-autologin.conf"
    elif [[ -f /etc/gdm3/daemon.conf ]]; then
        cp /etc/gdm3/daemon.conf /etc/gdm3/daemon.conf.backup
        sed -i -E "s/^#?[[:space:]]*AutomaticLoginEnable[[:space:]]*=.*/AutomaticLoginEnable = true/; s/^#?[[:space:]]*AutomaticLogin[[:space:]]*=.*/AutomaticLogin = $NEW_USER/" /etc/gdm3/daemon.conf
        echo "Auto-login enabled in /etc/gdm3/daemon.conf"
    else
        echo "No supported display manager (lightdm/gdm3) found; auto-login skipped."
    fi
fi

# Verify sudo group membership
echo
echo "Verifying group membership..."
groups "$NEW_USER"

# Summary
echo
echo "============================="
echo "Setup Complete!"
echo "============================="
echo "New user: $NEW_USER"
echo
echo "IMPORTANT - REQUIRED STEPS:"
echo "=============================="
echo "1. LOGOUT of the current session"
echo "2. LOGIN as $NEW_USER"
echo "3. Group changes only apply after re-login!"
echo
echo "After logging in as $NEW_USER, verify with:"
echo "  groups"
echo "  sudo -v"
echo
echo "If sudo doesn't work, run as root:"
echo "  su -"
echo "  usermod -aG sudo $NEW_USER"
echo "  exit"
echo "  Then logout and login again"
echo
echo "Done!"
