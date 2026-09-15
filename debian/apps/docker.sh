#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DOCKER CE (official Docker apt repository)
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Installing Docker CE on Debian/Ubuntu..."

if is_ubuntu; then
    repo_distro="ubuntu"
else
    repo_distro="debian"
fi
codename="$(os_codename)"
arch="$(dpkg --print-architecture)"

# Remove conflicting distro packages
conflicts=(docker.io docker-doc docker-compose podman-docker containerd runc)
installed_conflicts=()
for p in "${conflicts[@]}"; do
    pkg_installed "$p" && installed_conflicts+=("$p")
done
if [ "${#installed_conflicts[@]}" -gt 0 ] && ! is_simulate; then
    log "Removing conflicting packages: ${installed_conflicts[*]}"
    apt_remove "${installed_conflicts[@]}"
fi

add_apt_repo docker "https://download.docker.com/linux/${repo_distro}/gpg" \
    "deb [arch=${arch} signed-by={keyring}] https://download.docker.com/linux/${repo_distro} ${codename} stable"

apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

enable_service docker.service --now
add_user_group docker

log "Docker installation complete. Log out and back in for docker group membership."
