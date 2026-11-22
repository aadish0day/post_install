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
TARGET_USER="${SYS_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
sudo usermod -aG video,render "$TARGET_USER"

# 4. Prepare temporary AUR build directory
# /tmp is tmpfs (RAM) on Arch; the zip is ~4.5 GB and the build extracts ~10-15 GB, so build on disk.
BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/davinci_resolve_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

avail_kib="$(df --output=avail -k "$BUILD_DIR" 2>/dev/null | tail -n1 | tr -d ' ')"
if [ -n "${avail_kib:-}" ] && [ "$avail_kib" -lt $((30 * 1024 * 1024)) ]; then
    log "ERROR: less than 30 GiB free on $(dirname "$BUILD_DIR"); DaVinci Resolve needs ~30 GiB to build."
    exit 1
fi

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

    # Blackmagic requires registration to download. Use your own details via environment variables
    # (no placeholder data is submitted on your behalf).
    missing_env=()
    for v in BMD_FIRSTNAME BMD_LASTNAME BMD_EMAIL BMD_PHONE BMD_COUNTRY BMD_STATE BMD_CITY BMD_STREET; do
        [ -n "${!v:-}" ] || missing_env+=("$v")
    done
    if [ ${#missing_env[@]} -gt 0 ]; then
        log "Automatic download needs your registration details; missing: ${missing_env[*]}"
        log "Either export them and re-run, or download '$expected_zip' manually from:"
        log "  https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"
        log "and save it to ~/Downloads, then re-run this script."
        exit 1
    fi
    _reqjson="$(jq -n \
        --arg firstname "$BMD_FIRSTNAME" --arg lastname "$BMD_LASTNAME" --arg email "$BMD_EMAIL" \
        --arg phone "$BMD_PHONE" --arg country "$BMD_COUNTRY" --arg state "$BMD_STATE" \
        --arg city "$BMD_CITY" --arg street "$BMD_STREET" \
        '{firstname:$firstname,lastname:$lastname,email:$email,phone:$phone,country:$country,state:$state,city:$city,street:$street,product:"DaVinci Resolve"}')"

    log "Requesting signed download URL for DaVinci Resolve ${pkgver}..."
    _dlurl=$(curl -s --max-time 60 -X POST "https://www.blackmagicdesign.com/api/register/us/download/${_downloadId}" \
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

# The gfx override is only correct for Radeon 680M/660M (gfx1035, PCI 1002:1681); elsewhere it breaks ROCm.
HSA_PREFIX=""
HSA_EXPORT=""
if lspci -nn 2>/dev/null | grep -qi '1002:1681'; then
    HSA_PREFIX="env HSA_OVERRIDE_GFX_VERSION=10.3.0 "
    HSA_EXPORT="export HSA_OVERRIDE_GFX_VERSION=10.3.0"
fi

if [ -f "$DESKTOP_DIR/DaVinciResolve.desktop" ]; then
    sed -i "s|^Exec=.*|Exec=${HSA_PREFIX}/opt/resolve/bin/resolve %u|" "$DESKTOP_DIR/DaVinciResolve.desktop"
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    log "Updated user desktop entry at $DESKTOP_DIR/DaVinciResolve.desktop"
fi

# 8. Create a convenient CLI launcher wrapper
mkdir -p "$HOME/.local/bin"
cat <<EOF > "$HOME/.local/bin/davinci-resolve"
#!/usr/bin/env bash
# Wrapper to launch DaVinci Resolve (HSA override only on Radeon 680M/660M)
${HSA_EXPORT}
exec /opt/resolve/bin/resolve "\$@"
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
