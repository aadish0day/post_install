#!/usr/bin/env bash
# Thin package manager wrapper for Debian/Ubuntu (apt/nala)

pkg_install() {
    local cmd="apt-get"
    if command -v nala &>/dev/null; then cmd="nala"; fi
    ${SUDO:-sudo} "$cmd" install -y "$@"
}

pkg_remove() {
    local cmd="apt-get"
    if command -v nala &>/dev/null; then cmd="nala"; fi
    ${SUDO:-sudo} "$cmd" remove -y "$@"
}

pkg_installed() {
    dpkg -s "$1" &>/dev/null
}

pkg_update() {
    local cmd="apt-get"
    if command -v nala &>/dev/null; then cmd="nala"; fi
    ${SUDO:-sudo} "$cmd" update -y
}
