#!/usr/bin/env bash
#
# fetch-iso.sh - Fetch and download latest Arch, Debian, Ubuntu Server, Kali, and VMware Tools Windows ISOs
# Powered by aria2c (multi-connection acceleration) with user-agent rotation & intelligent fallback.
#

set -eo pipefail

DOWNLOAD_DIR="${HOME}/Downloads/ISOs"
CONCURRENT_CONNS=16
PIECE_SIZE="1M"

# User-Agent rotation pool
USER_AGENTS=(
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0"
)
RANDOM_UA="${USER_AGENTS[$RANDOM % ${#USER_AGENTS[@]}]}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$DOWNLOAD_DIR"

usage() {
    echo -e "${BLUE}=== Latest ISO Downloader (aria2c multi-thread) ===${NC}"
    echo "Usage: $0 [options] [iso_names...]"
    echo ""
    echo "Available ISO targets:"
    echo "  arch          - Latest Arch Linux (x86_64)"
    echo "  debian        - Latest Debian Stable (Netinst amd64)"
    echo "  ubuntu        - Latest Ubuntu Server LTS (amd64)"
    echo "  kali          - Latest Kali Linux Installer (amd64)"
    echo "  vmware        - Latest VMware Tools for Windows (ISO)"
    echo "  all           - Download all 5 latest ISOs"
    echo ""
    echo "Options:"
    echo "  -o, --output DIR     Custom download directory (default: $DOWNLOAD_DIR)"
    echo "  -s, --connections N  Connections per server (default: $CONCURRENT_CONNS)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 all                       # Download all latest ISOs"
    echo "  $0 arch kali                 # Download only Arch and Kali"
    echo "  $0 vmware -o ~/VM_ISOs       # Download VMware tools ISO to ~/VM_ISOs"
    echo "  $0                           # Interactive menu"
    exit 0
}

# Fetchers for latest official release URLs
get_arch_url() {
    echo "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
}

get_debian_url() {
    local html
    html=$(curl -sL --user-agent "$RANDOM_UA" "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/")
    local file
    file=$(echo "$html" | grep -oP 'href="\Kdebian-[0-9.]+-amd64-netinst\.iso' | head -n 1)
    if [[ -n "$file" ]]; then
        echo "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/${file}"
    fi
}

get_ubuntu_url() {
    local html
    html=$(curl -sL --user-agent "$RANDOM_UA" "https://releases.ubuntu.com/noble/")
    local file
    file=$(echo "$html" | grep -oP 'href="\Kubuntu-[0-9.]+-live-server-amd64\.iso' | head -n 1)
    if [[ -n "$file" ]]; then
        echo "https://releases.ubuntu.com/noble/${file}"
    fi
}

get_kali_url() {
    local html
    html=$(curl -sL --user-agent "$RANDOM_UA" "https://cdimage.kali.org/current/")
    local file
    file=$(echo "$html" | grep -oP 'href="\Kkali-linux-[0-9.]+-installer-amd64\.iso' | head -n 1)
    if [[ -n "$file" ]]; then
        echo "https://cdimage.kali.org/current/${file}"
    fi
}

get_vmware_url() {
    local html
    html=$(curl -sL --user-agent "$RANDOM_UA" "https://packages.vmware.com/tools/releases/latest/windows/")
    local file
    file=$(echo "$html" | grep -oP 'href="\KVMware-tools-windows-(?!arm)[0-9.-]+\.iso' | head -n 1)
    if [[ -n "$file" ]]; then
        echo "https://packages.vmware.com/tools/releases/latest/windows/${file}"
    fi
}

download_file() {
    local name="$1"
    local url="$2"
    local force_curl="${3:-false}"

    if [[ -z "$url" ]]; then
        echo -e "${RED}[!] Error: Could not resolve latest URL for $name.${NC}"
        return 1
    fi

    local filename
    filename=$(basename "$url")

    echo ""
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${GREEN}[+] Target:   ${name}${NC}"
    echo -e "${GREEN}[+] File:     ${filename}${NC}"
    echo -e "${GREEN}[+] URL:      ${url}${NC}"
    echo -e "${GREEN}[+] Destination: ${DOWNLOAD_DIR}/${filename}${NC}"
    echo -e "${CYAN}======================================================${NC}"

    if [ "$force_curl" = true ]; then
        # For servers like packages.vmware.com that reject multi-range requests
        echo -e "${YELLOW}[*] Downloading via accelerated stream (curl)...${NC}"
        curl -# -L -C - \
            --user-agent "$RANDOM_UA" \
            -o "${DOWNLOAD_DIR}/${filename}" \
            "$url"
    else
        echo -e "${YELLOW}[*] Downloading via aria2c (${CONCURRENT_CONNS} parallel connections)...${NC}"
        if ! aria2c \
            --dir="$DOWNLOAD_DIR" \
            --out="$filename" \
            --continue=true \
            --max-connection-per-server="$CONCURRENT_CONNS" \
            --split="$CONCURRENT_CONNS" \
            --min-split-size="$PIECE_SIZE" \
            --file-allocation=none \
            --user-agent="$RANDOM_UA" \
            --summary-interval=1 \
            --console-log-level=warn \
            "$url"; then

            echo -e "${YELLOW}[!] aria2c multi-connection failed or server does not support byte ranges. Falling back to curl...${NC}"
            curl -# -L -C - \
                --user-agent "$RANDOM_UA" \
                -o "${DOWNLOAD_DIR}/${filename}" \
                "$url"
        fi
    fi

    echo -e "${GREEN}[✔] Completed: ${filename}${NC}"
}

# Parse options
TARGETS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
    -o | --output)
        DOWNLOAD_DIR="$2"
        mkdir -p "$DOWNLOAD_DIR"
        shift 2
        ;;
    -s | --connections)
        CONCURRENT_CONNS="$2"
        shift 2
        ;;
    -h | --help)
        usage
        ;;
    arch | debian | ubuntu | kali | vmware | all)
        TARGETS+=("$1")
        shift
        ;;
    *)
        echo -e "${RED}[!] Unknown option or target: $1${NC}"
        usage
        ;;
    esac
done

# If no targets given on CLI, prompt interactive menu
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}     Latest OS & VMware ISO Downloader        ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo "1) All (Arch, Debian, Ubuntu Server, Kali, VMware)"
    echo "2) Arch Linux (Latest x86_64)"
    echo "3) Debian Stable (Latest Netinst amd64)"
    echo "4) Ubuntu Server (Latest LTS amd64)"
    echo "5) Kali Linux (Latest Installer amd64)"
    echo "6) VMware Tools for Windows (Latest ISO)"
    echo "7) Exit"
    echo ""
    read -rp "Select option [1-7]: " choice

    case "$choice" in
    1) TARGETS=("all") ;;
    2) TARGETS=("arch") ;;
    3) TARGETS=("debian") ;;
    4) TARGETS=("ubuntu") ;;
    5) TARGETS=("kali") ;;
    6) TARGETS=("vmware") ;;
    7)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid selection. Exiting.${NC}"
        exit 1
        ;;
    esac
fi

# Expand 'all'
FINAL_TARGETS=()
for t in "${TARGETS[@]}"; do
    if [[ "$t" == "all" ]]; then
        FINAL_TARGETS=("arch" "debian" "ubuntu" "kali" "vmware")
        break
    else
        FINAL_TARGETS+=("$t")
    fi
done

echo -e "${YELLOW}[*] Resolving latest URLs...${NC}"

for target in "${FINAL_TARGETS[@]}"; do
    case "$target" in
    arch)
        url=$(get_arch_url)
        download_file "Arch Linux" "$url" false
        ;;
    debian)
        echo -e "${YELLOW}[*] Finding latest Debian release...${NC}"
        url=$(get_debian_url)
        download_file "Debian Stable" "$url" false
        ;;
    ubuntu)
        echo -e "${YELLOW}[*] Finding latest Ubuntu Server LTS release...${NC}"
        url=$(get_ubuntu_url)
        download_file "Ubuntu Server LTS" "$url" false
        ;;
    kali)
        echo -e "${YELLOW}[*] Finding latest Kali release...${NC}"
        url=$(get_kali_url)
        download_file "Kali Linux" "$url" false
        ;;
    vmware)
        echo -e "${YELLOW}[*] Finding latest VMware Tools for Windows release...${NC}"
        url=$(get_vmware_url)
        # VMware's Cloudflare cache rejects HTTP range splitting, so use direct accelerated stream
        download_file "VMware Tools Windows" "$url" true
        ;;
    esac
done

echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}[✔] All requested downloads are complete!${NC}"
echo -e "${GREEN}[+] Saved to: ${DOWNLOAD_DIR}${NC}"
echo -e "${GREEN}======================================================${NC}"
