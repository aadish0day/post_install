#!/usr/bin/env bash
# Thin package manager wrapper for Fedora (dnf/dnf5)

pkg_install() {
    local cmd="dnf"
    if command -v dnf5 &>/dev/null; then cmd="dnf5"; fi
    ${SUDO:-sudo} "$cmd" install -y "$@"
}

pkg_remove() {
    local cmd="dnf"
    if command -v dnf5 &>/dev/null; then cmd="dnf5"; fi
    ${SUDO:-sudo} "$cmd" remove -y "$@"
}

pkg_installed() {
    rpm -q "$1" &>/dev/null
}

pkg_update() {
    local cmd="dnf"
    if command -v dnf5 &>/dev/null; then cmd="dnf5"; fi
    ${SUDO:-sudo} "$cmd" upgrade -y --refresh
}
