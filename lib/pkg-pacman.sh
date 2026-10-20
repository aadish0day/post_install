#!/usr/bin/env bash
# Thin package manager wrapper for Arch Linux (pacman)

pkg_install() {
    ${SUDO:-sudo} pacman -S --needed --noconfirm "$@"
}

pkg_remove() {
    ${SUDO:-sudo} pacman -Rns --noconfirm "$@"
}

pkg_installed() {
    pacman -Q "$1" &>/dev/null
}

pkg_update() {
    ${SUDO:-sudo} pacman -Syu --noconfirm
}
