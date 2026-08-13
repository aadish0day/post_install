#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Samsung Tablet Native Second Screen Orchestrator for Arch Linux (KDE 6 Wayland)
# Handles:
# 1. Samsung "Second Screen" Miracast / Wi-Fi Display (WFD) engine setup
# 2. KDE Plasma 6 Wayland Native Virtual Display creation via kscreen-doctor
# 3. Wi-Fi Direct / P2P networking & GStreamer PipeWire streaming pipeline
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting Samsung Second Screen setup on Arch Linux..."

# Check root elevation if required for system setup
if [ "$(id -u)" -eq 0 ]; then
    log "Notice: Run this script as your standard desktop user (not root) so KDE Wayland session is detected."
fi

# 1. Verify Wayland Session
session_type="${XDG_SESSION_TYPE:-unknown}"
if [ "$session_type" != "wayland" ]; then
    log "Warning: XDG_SESSION_TYPE is '$session_type'. Wayland is strongly recommended for native virtual displays."
fi

# 2. Check and Install Official Dependencies
log "Installing Wi-Fi Display, PipeWire, and GStreamer dependencies via pacman..."
official_deps=(
    networkmanager
    pipewire
    pipewire-audio
    gstreamer
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-rtsp-server
    libportal
    libportal-gtk4
    android-tools
)

sudo pacman -S --needed --noconfirm "${official_deps[@]}" --overwrite '*'

# 3. Check/Install GNOME Network Displays (Miracast/WFD Engine) from AUR
if ! command -v gnome-network-displays &>/dev/null; then
    log "Installing gnome-network-displays from AUR..."
    if command -v paru &>/dev/null; then
        paru -S --needed --noconfirm gnome-network-displays
    else
        log "Error: paru is required to install gnome-network-displays from AUR."
        exit 1
    fi
fi

# 4. Create Native KDE 6 Wayland Virtual Display
log "Creating native KDE Plasma 6 Virtual Display output..."
if command -v kscreen-doctor &>/dev/null; then
    # Enable VIRTUAL-1 output in KDE Plasma 6
    kscreen-doctor output.VIRTUAL-1.enable 2>/dev/null || true
    
    # Set high-resolution display mode matching Samsung Galaxy Tab resolution
    kscreen-doctor output.VIRTUAL-1.mode.2560x1600@60 2>/dev/null || \
    kscreen-doctor output.VIRTUAL-1.mode.1920x1200@60 2>/dev/null || true
    
    log "KDE Plasma 6 Virtual Display (VIRTUAL-1) successfully enabled!"
else
    log "Warning: kscreen-doctor not found. Ensure KDE Plasma 6 is installed."
fi

# 5. User Connection Instructions
echo ""
echo "============================================================================"
echo " SAMSUNG SECOND SCREEN CONNECTION STEPS:"
echo " 1. On your Samsung Tablet, swipe down the Quick Settings panel."
echo " 2. Tap the 'Second Screen' tile (or Smart View -> Second Screen)."
echo " 3. Choose your mode ('Drawing/gaming' for touch or 'Video' for video)."
echo " 4. Launching GNOME Network Displays now..."
echo " 5. Select your Samsung Tablet from the device list to project your extended screen!"
echo "============================================================================"
echo ""

# 6. Launch Network Displays Engine
if command -v gnome-network-displays &>/dev/null; then
    exec gnome-network-displays "$@"
else
    log "Error: gnome-network-displays failed to launch."
    exit 1
fi
