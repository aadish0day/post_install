#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX DAVINCI RESOLVE INSTALLER & AMD ROCM/OPENCL SETUP
# ============================================================================
# Automates:
# 1. OpenCL runtime installation (rocm-opencl-runtime) & user group permissions
# 2. Downloading DaVinci Resolve installer zip via Blackmagic API (or using local)
# 3. Building & installing the davinci-resolve AUR package via makepkg
# 4. Configuring GPU environment override (HSA_OVERRIDE_GFX_VERSION=10.3.0)
#    required for AMD Radeon 680M (Rembrandt RDNA2 APU)
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 1. Check Root vs Sudo
if [ "$EUID" -eq 0 ]; then
    log "ERROR: Do not run this script directly as root. makepkg cannot run as root."
    log "Please run as a regular user with sudo permissions: ./davinci-resolve.sh"
    exit 1
fi

log "Starting DaVinci Resolve installation setup on Arch Linux..."

# 2. Install required build and runtime dependencies
log "Installing prerequisite packages (base-devel, git, curl, jq, aria2, rocm-opencl-runtime, clinfo)..."
sudo pacman -S --needed --noconfirm base-devel git curl jq aria2 rocm-opencl-runtime clinfo

# 3. Ensure user is in video and render groups for OpenCL / GPU access
log "Configuring GPU device permissions (video & render groups)..."
sudo usermod -aG video,render "$USER"

# 4. Prepare temporary AUR build directory
BUILD_DIR="/tmp/davinci_resolve_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Cloning davinci-resolve AUR package..."
git clone https://aur.archlinux.org/davinci-resolve.git "$BUILD_DIR"

pkgver=$(grep -E '^[[:space:]]*pkgver=' "$BUILD_DIR/PKGBUILD" | head -n1 | cut -d'=' -f2 | tr -d " '\"")
expected_zip="DaVinci_Resolve_${pkgver}_Linux.zip"
log "Target version: $pkgver (expected installer: $expected_zip)"

# 5. Locate or Download the source archive
mkdir -p "$HOME/Downloads"
TARGET_DOWNLOAD="$HOME/Downloads/$expected_zip"

if [ -f "$TARGET_DOWNLOAD" ] && [ ! -f "${TARGET_DOWNLOAD}.aria2" ]; then
    log "Found existing completed $expected_zip in ~/Downloads. Using local file..."
elif [ -f "./$expected_zip" ]; then
    log "Found existing $expected_zip in current directory. Copying to ~/Downloads..."
    cp -v "./$expected_zip" "$TARGET_DOWNLOAD"
else
    log "Querying Blackmagic Design API for download authorization..."
    _siteurl="https://www.blackmagicdesign.com/api/support/latest-stable-version/davinci-resolve/linux"
    _releaseinfo=$(curl -s "$_siteurl")
    _downloadId=$(printf "%s" "$_releaseinfo" | jq -r '.linux.downloadId // empty' 2>/dev/null || true)
    if [ -z "$_downloadId" ]; then
        _downloadId=$(printf "%s" "$_releaseinfo" | sed -n 's/.*"downloadId":"\([^"]*\).*/\1/p')
    fi

    if [ -z "$_downloadId" ]; then
        log "WARNING: Could not automatically acquire download ID from Blackmagic API."
        log "Please download '$expected_zip' manually from:"
        log "  https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"
        log "Save it to ~/Downloads and re-run this script."
        exit 1
    fi

    _reqjson='{
      "firstname": "Linux",
      "lastname": "User",
      "email": "user@archlinux.org",
      "phone": "202-555-0194",
      "country": "us",
      "street": "Main St",
      "state": "NY",
      "city": "AUR",
      "product": "DaVinci Resolve"
    }'

    log "Requesting signed download URL for DaVinci Resolve ${pkgver}..."
    _dlurl=$(curl -s -X POST "https://www.blackmagicdesign.com/api/register/us/download/${_downloadId}" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        -d "$_reqjson")

    if [[ "$_dlurl" != http* ]]; then
        log "WARNING: Blackmagic API did not return a valid download URL: $_dlurl"
        log "Please download '$expected_zip' manually to ~/Downloads and re-run this script."
        exit 1
    fi

    log "Downloading $expected_zip (~4.5 GB) with aria2c multi-connection acceleration (16 threads)..."
    if command -v aria2c &>/dev/null; then
        aria2c -x 16 -s 16 -k 1M -j 16 -c \
            --summary-interval=1 \
            --file-allocation=none \
            --dir="$HOME/Downloads" \
            --out="$expected_zip" \
            "$_dlurl"
    else
        log "aria2c not found, falling back to curl..."
        curl -L -C - --progress-bar "$_dlurl" -o "$TARGET_DOWNLOAD"
    fi
fi

# Link or copy the downloaded file into the build directory
log "Linking $expected_zip into build directory..."
ln -f "$TARGET_DOWNLOAD" "$BUILD_DIR/$expected_zip" 2>/dev/null || cp "$TARGET_DOWNLOAD" "$BUILD_DIR/$expected_zip"

# 6. Build and install via makepkg
log "Building and installing davinci-resolve (this compiles packaging and extracts squashfs)..."
(cd "$BUILD_DIR" && makepkg -si --noconfirm)

# 7. Configure AMD APU OpenCL override wrapper
# AMD Rembrandt Radeon 680M APU (gfx1035) requires HSA_OVERRIDE_GFX_VERSION=10.3.0
# for ROCm OpenCL acceleration in DaVinci Resolve.
log "Configuring AMD Radeon 680M GPU acceleration launcher..."
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

if [ -f "/opt/resolve/share/DaVinciResolve.desktop" ]; then
    cp -f "/opt/resolve/share/DaVinciResolve.desktop" "$DESKTOP_DIR/DaVinciResolve.desktop"
elif [ -f "/usr/share/applications/DaVinciResolve.desktop" ]; then
    cp -f "/usr/share/applications/DaVinciResolve.desktop" "$DESKTOP_DIR/DaVinciResolve.desktop"
fi

if [ -f "$DESKTOP_DIR/DaVinciResolve.desktop" ]; then
    sed -i 's|^Exec=.*|Exec=env HSA_OVERRIDE_GFX_VERSION=10.3.0 /opt/resolve/bin/resolve %u|' "$DESKTOP_DIR/DaVinciResolve.desktop"
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    log "Updated user desktop entry at $DESKTOP_DIR/DaVinciResolve.desktop with HSA_OVERRIDE_GFX_VERSION=10.3.0"
fi

# 8. Create a convenient CLI launcher wrapper
mkdir -p "$HOME/.local/bin"
cat <<'EOF' > "$HOME/.local/bin/davinci-resolve"
#!/usr/bin/env bash
# Wrapper to launch DaVinci Resolve with AMD ROCm / OpenCL compatibility
export HSA_OVERRIDE_GFX_VERSION=10.3.0
exec /opt/resolve/bin/resolve "$@"
EOF
chmod +x "$HOME/.local/bin/davinci-resolve"

log "============================================================================"
log "DaVinci Resolve installation and setup finished successfully!"
log "============================================================================"
log "Notes for AMD Radeon 680M users:"
log " 1. If you just added your user to 'video' and 'render' groups, please"
log "    log out and log back in (or reboot) for group permissions to apply."
log " 2. Launcher created at ~/.local/bin/davinci-resolve (and in desktop menu)."
log " 3. Codec note: DaVinci Resolve Free on Linux does not natively decode"
log "    AAC audio or standard H.264/H.265 in MP4 containers."
log "    To convert footage for editing, use ffmpeg:"
log "      ffmpeg -i input.mp4 -c:v prores_ks -profile:v 3 -c:a pcm_s16le output.mov"
log "============================================================================"
