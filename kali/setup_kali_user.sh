#!/bin/bash

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
read -p "Enter the new username: " NEW_USER

# Validate username
if [[ -z "$NEW_USER" ]]; then
    echo "Error: Username cannot be empty"
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
GROUPS="dialout wireshark bluetooth netdev kaboxer vboxsf docker"

for group in $GROUPS; do
    if getent group "$group" > /dev/null 2>&1; then
        usermod -aG "$group" "$NEW_USER"
    fi
done

# Set proper ownership
chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"

# Create common directories
su - "$NEW_USER" -c "mkdir -p ~/Documents ~/Downloads ~/Tools ~/Scripts"

# Handle default kali user removal
if [[ "$KALI_EXISTS" == true ]]; then
    echo
    read -p "Remove the default 'kali' user? (yes/no): " REMOVE_KALI
    
    if [[ "$REMOVE_KALI" == "yes" || "$REMOVE_KALI" == "y" ]]; then
        echo "Removing kali user..."
        pkill -u kali 2>/dev/null
        sleep 2
        userdel -r kali 2>/dev/null
        rm -f /etc/sudoers.d/kali 2>/dev/null
        echo "Kali user removed"
    fi
fi

# Auto-login configuration
echo
read -p "Enable auto-login for $NEW_USER? (yes/no): " AUTO_LOGIN

if [[ "$AUTO_LOGIN" == "yes" || "$AUTO_LOGIN" == "y" ]]; then
    if [[ -f /etc/lightdm/lightdm.conf ]]; then
        cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
    fi
    
    if grep -q "autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
        sed -i "s/^autologin-user=.*/autologin-user=$NEW_USER/" /etc/lightdm/lightdm.conf
    else
        echo -e "\n[Seat:*]\nautologin-user=$NEW_USER\nautologin-user-timeout=0" >> /etc/lightdm/lightdm.conf
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
