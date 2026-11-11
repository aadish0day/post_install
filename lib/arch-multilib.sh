#!/usr/bin/env bash
# Shared helper for arch/* modules: enable [multilib] once, cleanly.
# Source it; then call ensure_multilib. Works as root or via sudo.

ensure_multilib() {
    local sudo_cmd=()
    [ "${EUID:-$(id -u)}" -ne 0 ] && sudo_cmd=(sudo)
    [ -f /etc/pacman.conf ] || return 0
    grep -q '^\[multilib\]' /etc/pacman.conf && return 0

    echo "Enabling multilib repository in /etc/pacman.conf..."
    # Uncomment only the [multilib] header and its Include line.
    "${sudo_cmd[@]}" sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        echo "ERROR: could not enable [multilib]; edit /etc/pacman.conf manually." >&2
        return 1
    fi
    "${sudo_cmd[@]}" pacman -Syu --noconfirm
}

# Regenerate bootloader config so new microcode / cmdline takes effect.
refresh_bootloader() {
    local sudo_cmd=()
    [ "${EUID:-$(id -u)}" -ne 0 ] && sudo_cmd=(sudo)
    if [ -f /etc/default/grub ] && command -v grub-mkconfig &>/dev/null; then
        local out=/boot/grub/grub.cfg
        [ -d /boot/grub ] || out=/boot/grub2/grub.cfg
        echo "Regenerating GRUB config ($out)..."
        "${sudo_cmd[@]}" grub-mkconfig -o "$out" || echo "WARN: grub-mkconfig failed; run it manually." >&2
    elif command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null; then
        echo "WARN: systemd-boot detected. Add the microcode initrd to your loader entry"
        echo "      (initrd /amd-ucode.img or /intel-ucode.img before the main initrd), or use a UKI."
    else
        echo "WARN: unknown bootloader; make sure it loads the microcode image."
    fi
}
