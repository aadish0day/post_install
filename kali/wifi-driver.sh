
#!/usr/bin/env bash
set -euo pipefail

# Function to log script actions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
        if ! sudo apt-get install -y "${to_install[@]}"; then
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

log "Starting RTL8812AU WiFi driver installation..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Check if sudo is available
if ! command_exists sudo; then
    log "sudo is not available. Please install sudo or run as root."
    exit 1
fi

# Update package lists
log "Updating package lists..."
sudo apt-get update

# Install required packages
log "Installing required packages..."
required_packages=(
    dkms
    bc
    mokutil
    build-essential
    libelf-dev
    "linux-headers-$(uname -r)"
    git
)

install_if_needed "${required_packages[@]}"

# Check if kernel headers are available
if ! dpkg -l | grep -q "linux-headers-$(uname -r)"; then
    log "Error: Linux headers for current kernel ($(uname -r)) are not installed."
    log "Please install them manually: sudo apt-get install linux-headers-$(uname -r)"
    exit 1
fi

# Create a temporary directory for the driver
TEMP_DIR="/tmp/rtl8812au-$(date +%s)"
log "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Clone the driver repository
log "Cloning RTL8812AU driver repository..."
if git clone https://github.com/aircrack-ng/rtl8812au.git; then
    log "Repository cloned successfully."
else
    log "Failed to clone repository. Please check your internet connection."
    exit 1
fi

# Navigate to the driver directory
cd rtl8812au || {
    log "Failed to enter driver directory."
    exit 1
}

# Check if Makefile exists
if [ ! -f "Makefile" ]; then
    log "Error: Makefile not found in driver directory."
    exit 1
fi

# Install the driver using DKMS
log "Installing RTL8812AU driver using DKMS..."
if sudo make dkms_install; then
    log "Driver installed successfully using DKMS."
else
    log "Failed to install driver using DKMS. Trying alternative method..."
    
    # Alternative installation method
    log "Trying direct compilation and installation..."
    if make && sudo make install; then
        log "Driver installed successfully using direct compilation."
    else
        log "Failed to install driver using direct compilation."
        log "Please check the error messages above and try manual installation."
        exit 1
    fi
fi

# Load the module
log "Loading the RTL8812AU module..."
if sudo modprobe 8812au; then
    log "Module loaded successfully."
else
    log "Failed to load module. You may need to reboot your system."
fi

# Clean up temporary directory
log "Cleaning up temporary files..."
cd /
rm -rf "$TEMP_DIR"

# Check if the driver is loaded
if lsmod | grep -q "8812au"; then
    log "RTL8812AU driver is loaded and ready to use."
else
    log "Driver installation completed, but module is not loaded."
    log "Please reboot your system to load the driver."
fi

log "RTL8812AU WiFi driver installation completed!"
log "If you encounter any issues, please reboot your system."
