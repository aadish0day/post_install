#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────
#  Nerd Font Installer for Termux
#  Font: JetBrainsMono Nerd Font
#  Source: github.com/ryanoasis/nerd-fonts
# ─────────────────────────────────────────────

set -euo pipefail

FONT_NAME="JetBrainsMono"
FONT_ZIP="${FONT_NAME}.zip"
FONT_DIR="${HOME}/${FONT_NAME}NF"
FONT_FILE="JetBrainsMonoNerdFont-Regular.ttf"
TERMUX_FONT="${HOME}/.termux/font.ttf"
DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_ZIP}"

# ── Helpers ───────────────────────────────────
info()    { echo -e "\e[34m[INFO]\e[0m  $*"; }
success() { echo -e "\e[32m[OK]\e[0m    $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m  $*"; }
error()   { echo -e "\e[31m[ERR]\e[0m   $*"; exit 1; }

# ── Step 1: Update & install deps ─────────────
info "Updating Termux packages..."
pkg update -y && pkg upgrade -y

info "Installing wget and unzip..."
pkg install wget unzip -y
success "Dependencies ready."

# ── Step 2: Download font zip ─────────────────
info "Downloading ${FONT_NAME} Nerd Font (latest release)..."
cd ~
wget -q --show-progress -O "${FONT_ZIP}" "${DOWNLOAD_URL}" \
  || error "Download failed. Check your internet connection."
success "Download complete: ${FONT_ZIP}"

# ── Step 3: Extract ───────────────────────────
info "Extracting font archive..."
unzip -o "${FONT_ZIP}" -d "${FONT_DIR}" > /dev/null
success "Extracted to ${FONT_DIR}/"

# ── Step 4: Verify target TTF exists ──────────
if [[ ! -f "${FONT_DIR}/${FONT_FILE}" ]]; then
  warn "Expected file not found: ${FONT_FILE}"
  warn "Available TTFs in archive:"
  ls "${FONT_DIR}"/*.ttf 2>/dev/null || echo "  (none found)"
  error "Cannot continue — font file missing."
fi

# ── Step 5: Apply font to Termux ──────────────
info "Applying font to Termux..."
mkdir -p ~/.termux
cp "${FONT_DIR}/${FONT_FILE}" "${TERMUX_FONT}"
termux-reload-settings
success "Font applied: ${FONT_FILE} → ${TERMUX_FONT}"

# ── Step 6: Cleanup ───────────────────────────
info "Cleaning up..."
rm -f "${FONT_ZIP}"
rm -rf "${FONT_DIR}"
success "Cleanup done."

# ── Done ──────────────────────────────────────
echo ""
echo -e "\e[32m╔══════════════════════════════════════╗\e[0m"
echo -e "\e[32m║  JetBrainsMono Nerd Font installed!  ║\e[0m"
echo -e "\e[32m║  Restart Termux to see the change.   ║\e[0m"
echo -e "\e[32m╚══════════════════════════════════════╝\e[0m"
