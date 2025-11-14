#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
	echo "$1"
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

# Create cybersec directory structure
mkdir -p ~/cybersec/

# Install nala and update/upgrade system
sudo apt update
sudo apt install nala -y
sudo nala update && sudo nala upgrade -y

# Define package lists
base_packages=(
	git git-lfs stow zsh tmux curl wget vim neovim fzf zoxide lsd trash-cli htop open-vm-tools
)

# Install base packages
install_if_needed "${base_packages[@]}"

# Setup dotfiles
# Remove existing .zshrc if it exists
if [ -f ~/.zshrc ]; then
	rm ~/.zshrc
fi

# Clone dotfiles only if it doesn't already exist
if [ -d ~/dotfile ]; then
	echo "Directory ~/dotfile already exists. Skipping clone."
else
	if git clone https://github.com/aadish0day/dotfile.git ~/dotfile; then
		echo "Dotfiles cloned successfully."
	fi
fi

# Link dotfiles if the directory exists
if [ -d ~/dotfile ] && [ -f ~/dotfile/link.sh ]; then
	cd ~/dotfile
	./link.sh
	cd - >/dev/null
fi

# Prompt user to choose Kali metapackages
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
		sudo nala install kali-linux-everything -y
		;;
	2)
		sudo nala install kali-linux-large -y
		;;
	3)
		sudo nala install kali-linux-labs -y
		;;
	4)
		echo "Skipping metapackage installation."
		;;
	*)
		echo "Invalid choice: $choice"
		;;
	esac
done

# Update searchsploit database
log "Updating searchsploit exploit database..."
if command -v searchsploit &>/dev/null; then
	searchsploit -u
	log "Searchsploit database updated successfully."
else
	log "Searchsploit not found. It will be available after installing Kali metapackages."
fi

# Change default shell to zsh
if command -v zsh &>/dev/null; then
	chsh -s "$(command -v zsh)" "$USER"
fi

# Clean up
sudo nala clean
log "Kali Linux setup completed successfully!"
log "Please reboot your system to ensure all changes take effect."
