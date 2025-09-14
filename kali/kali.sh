#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to install packages if not already installed
install_if_needed() {
    local pkg
    local failures=()
    local to_install=()

    for pkg in "$@"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            to_install+=("$pkg")
        else
            log "$pkg is already installed. Skipping..."
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        log "Installing: ${to_install[*]}"
        if ! sudo nala install -y "${to_install[@]}"; then
            log "Some packages failed to install, checking..."
            for pkg in "${to_install[@]}"; do
                if ! dpkg -l | grep -q "^ii  $pkg "; then
                    log "Failed to install $pkg"
                    failures+=("$pkg")
                fi
            done
            if [ ${#failures[@]} -gt 0 ]; then
                log "Failed to install the following packages: ${failures[*]}"
                return 1
            fi
        fi
    fi
}

log "Starting Kali Linux setup..."

# Install nala and update/upgrade system
log "Installing nala package manager..."
sudo apt update
sudo apt install nala -y

log "Updating system and packages..."
sudo nala update && sudo nala full-upgrade -y

# Define package lists
base_packages=(
    git stow zsh tmux curl wget vim neovim fzf starship zoxide lsd trash-cli
)


# Install base packages
log "Installing base packages..."
install_if_needed "${base_packages[@]}"


# Setup dotfiles
log "Setting up dotfiles..."

# Remove existing .zshrc if it exists
if [ -f ~/.zshrc ]; then
    log "Removing existing .zshrc file..."
    rm ~/.zshrc
else
    log ".zshrc file does not exist, nothing to remove."
fi

# Clone dotfiles only if it doesn't already exist
if [ -d ~/dotfile ]; then
    log "Directory ~/dotfile already exists. Skipping clone."
else
    log "Cloning dotfiles..."
    if git clone https://github.com/aadish0day/dotfile.git ~/dotfile; then
        log "Dotfiles cloned successfully."
    else
        log "Failed to clone dotfiles. Continuing without dotfiles setup."
    fi
fi

# Link dotfiles if the directory exists
if [ -d ~/dotfile ] && [ -f ~/dotfile/link.sh ]; then
    log "Linking dotfiles..."
    cd ~/dotfile
    if ./link.sh; then
        log "Dotfiles linked successfully."
    else
        log "Failed to link dotfiles."
    fi
    cd - > /dev/null
else
    log "Dotfiles directory or link.sh not found. Skipping dotfiles setup."
fi

# Prompt user to choose Kali metapackages
log "Kali Linux metapackage selection..."
echo
echo "Choose Kali metapackages to install (you can select multiple by separating with space):"
echo "1) kali-linux-everything  - All Kali tools (large download, ~10GB+)"
echo "2) kali-linux-large       - Extended default toolset"
echo "3) kali-linux-labs        - Vulnerable lab environments"
echo "4) Skip this step"

read -rp "Enter your choices [1-4], separated by spaces: " -a choices

for choice in "${choices[@]}"; do
    case $choice in
    1)
        log "Installing kali-linux-everything..."
        if sudo nala install kali-linux-everything -y; then
            log "kali-linux-everything installed successfully."
        else
            log "Failed to install kali-linux-everything."
        fi
        ;;
    2)
        log "Installing kali-linux-large..."
        if sudo nala install kali-linux-large -y; then
            log "kali-linux-large installed successfully."
        else
            log "Failed to install kali-linux-large."
        fi
        ;;
    3)
        log "Installing kali-linux-labs..."
        if sudo nala install kali-linux-labs -y; then
            log "kali-linux-labs installed successfully."
        else
            log "Failed to install kali-linux-labs."
        fi
        ;;
    4)
        log "Skipping metapackage installation."
        ;;
    *)
        log "Invalid choice: $choice"
        ;;
    esac
done


# Change default shell to zsh
if command -v zsh &>/dev/null; then
    log "Changing default shell to zsh..."
    if chsh -s "$(command -v zsh)" "$USER"; then
        log "Default shell changed to zsh successfully."
    else
        log "Failed to change default shell to zsh."
    fi
else
    log "zsh not found, skipping shell change."
fi


# Clean up
log "Cleaning up package cache..."
sudo nala clean

log "Kali Linux setup completed successfully!"
log "Please reboot your system to ensure all changes take effect."
