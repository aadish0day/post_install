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

# Add user to all required groups
echo "Adding user to groups..."
GROUPS="sudo dialout wireshark bluetooth netdev kaboxer vboxsf docker"

for group in $GROUPS; do
    if getent group "$group" > /dev/null 2>&1; then
        usermod -aG "$group" "$NEW_USER"
    fi
done

# Copy shell configuration
cp /etc/skel/.bashrc /home/"$NEW_USER"/ 2>/dev/null
cp /etc/skel/.profile /home/"$NEW_USER"/ 2>/dev/null
cp /etc/skel/.bash_logout /home/"$NEW_USER"/ 2>/dev/null

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

# Summary
echo
echo "============================="
echo "Setup Complete!"
echo "============================="
echo "New user: $NEW_USER"
echo
echo "Next steps:"
echo "1. Logout and login as $NEW_USER"
echo "2. Test sudo access: sudo -v"
echo
echo "Done!"
