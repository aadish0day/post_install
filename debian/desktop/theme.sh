#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Desktop Theme and Fonts Configuration (Debian/Ubuntu)
# Configures Dracula GTK theme, Papirus icon theme, Dracula cursors,
# JetBrains Mono Nerd Font, and system/user theme settings.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
TARGET_HOME="${TARGET_HOME:-$HOME}"

# 1. Non-interactive EULA acceptance for Microsoft TrueType core fonts
if ! is_simulate; then
    command -v debconf-set-selections >/dev/null 2>&1 || apt_install debconf-utils
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | ${SUDO:-sudo} debconf-set-selections 2>/dev/null || true
    fi
fi

# 2. Package-based fonts and icon themes
log "Installing desktop fonts and Papirus icon theme..."
apt_install papirus-icon-theme fonts-noto fonts-noto-color-emoji fonts-jetbrains-mono ttf-mscorefonts-installer

# 3. Dracula GTK theme
THEMES_DIR="$TARGET_HOME/.themes"
LOCAL_THEMES_DIR="$TARGET_HOME/.local/share/themes"

if [ -d "$THEMES_DIR/Dracula" ] || [ -d "$LOCAL_THEMES_DIR/Dracula" ] || [ -d "/usr/share/themes/Dracula" ]; then
    log "Dracula GTK theme already installed"
else
    log "Installing Dracula GTK theme..."
    url="$(github_asset_url dracula/gtk 'Dracula\.tar\.xz$')" || true
    url="${url:-https://github.com/dracula/gtk/releases/latest/download/Dracula.tar.xz}"
    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would extract $url to $THEMES_DIR and $LOCAL_THEMES_DIR"
    else
        mkdir -p "$THEMES_DIR" "$LOCAL_THEMES_DIR"
        tmp_theme="$(mktemp -d /tmp/dracula_theme_XXXXXX)"
        if curl -fSL --retry 3 "$url" | tar -xJ -C "$tmp_theme"; then
            cp -r "$tmp_theme"/* "$THEMES_DIR/" 2>/dev/null || true
            cp -r "$tmp_theme"/* "$LOCAL_THEMES_DIR/" 2>/dev/null || true
            if [ -n "${SUDO:-}" ] || [ "$(id -u)" -eq 0 ]; then
                ${SUDO:-sudo} mkdir -p /usr/share/themes
                ${SUDO:-sudo} cp -r "$tmp_theme"/* /usr/share/themes/ 2>/dev/null || true
            fi
            chown -R "$TARGET_USER:$TARGET_USER" "$THEMES_DIR" "$LOCAL_THEMES_DIR" 2>/dev/null || true
            log "Installed Dracula GTK theme"
        else
            warn "Failed to download or extract Dracula GTK theme"
        fi
        rm -rf "$tmp_theme"
    fi
fi

# 4. Dracula cursor theme
ICONS_DIR="$TARGET_HOME/.icons"
LOCAL_ICONS_DIR="$TARGET_HOME/.local/share/icons"

if [ -d "$ICONS_DIR/Dracula-cursors" ] || [ -d "$LOCAL_ICONS_DIR/Dracula-cursors" ] || [ -d "/usr/share/icons/Dracula-cursors" ]; then
    log "Dracula cursors already installed"
else
    log "Installing Dracula cursor theme..."
    cursor_url="$(github_asset_url dracula/gtk 'Dracula-cursors\.tar\.xz$')" || true
    cursor_url="${cursor_url:-https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz}"
    if is_simulate; then
        url_ok "$cursor_url" >/dev/null && log "[simulate] would extract $cursor_url to $ICONS_DIR and $LOCAL_ICONS_DIR"
    else
        mkdir -p "$ICONS_DIR" "$LOCAL_ICONS_DIR"
        tmp_cursor="$(mktemp -d /tmp/dracula_cursor_XXXXXX)"
        if curl -fSL --retry 3 "$cursor_url" | tar -xJ -C "$tmp_cursor"; then
            cp -r "$tmp_cursor/Dracula-cursors" "$ICONS_DIR/" 2>/dev/null || true
            cp -r "$tmp_cursor/Dracula-cursors" "$LOCAL_ICONS_DIR/" 2>/dev/null || true
            if [ -n "${SUDO:-}" ] || [ "$(id -u)" -eq 0 ]; then
                ${SUDO:-sudo} mkdir -p /usr/share/icons
                ${SUDO:-sudo} cp -r "$tmp_cursor/Dracula-cursors" /usr/share/icons/ 2>/dev/null || true
            fi
            chown -R "$TARGET_USER:$TARGET_USER" "$ICONS_DIR" "$LOCAL_ICONS_DIR" 2>/dev/null || true
            log "Installed Dracula cursor theme"
        else
            warn "Failed to download or extract Dracula cursor theme"
        fi
        rm -rf "$tmp_cursor"
    fi
fi

# 5. JetBrains Mono Nerd Font
FONT_DIR="$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerd"
if [ -d "$FONT_DIR" ] || fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    log "JetBrains Mono Nerd Font already installed"
else
    log "Installing JetBrains Mono Nerd Font..."
    font_url="$(github_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz$')" || true
    font_url="${font_url:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz}"
    if is_simulate; then
        url_ok "$font_url" >/dev/null && log "[simulate] would extract $font_url to $FONT_DIR"
    else
        mkdir -p "$FONT_DIR"
        if curl -fSL --retry 3 "$font_url" | tar -xJ -C "$FONT_DIR"; then
            chown -R "$TARGET_USER:$TARGET_USER" "$FONT_DIR" 2>/dev/null || true
            if [ -n "${SUDO:-}" ] || [ "$(id -u)" -eq 0 ]; then
                ${SUDO:-sudo} mkdir -p /usr/local/share/fonts/JetBrainsMonoNerd
                ${SUDO:-sudo} cp -r "$FONT_DIR"/* /usr/local/share/fonts/JetBrainsMonoNerd/ 2>/dev/null || true
            fi
            if command -v fc-cache >/dev/null 2>&1; then
                fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
            fi
            log "Installed JetBrains Mono Nerd Font to $FONT_DIR"
        else
            warn "Failed to download or extract JetBrains Mono Nerd Font"
            rm -rf "$FONT_DIR"
        fi
    fi
fi

# 6. Apply themes, icons, and fonts across desktop environments and GTK configs
if ! is_simulate; then
    log "Configuring active desktop theme, icons, and fonts..."

    # GTK 3 & GTK 4 settings.ini
    for gtk_dir in "$TARGET_HOME/.config/gtk-3.0" "$TARGET_HOME/.config/gtk-4.0"; do
        mkdir -p "$gtk_dir"
        cat <<EOF >"$gtk_dir/settings.ini"
[Settings]
gtk-theme-name=Dracula
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrains Mono 10
gtk-cursor-theme-name=Dracula-cursors
gtk-application-prefer-dark-theme=1
EOF
        chown -R "$TARGET_USER:$TARGET_USER" "$gtk_dir" 2>/dev/null || true
    done

    # GTK 4 libadwaita CSS link/copy from Dracula
    if [ -d "$THEMES_DIR/Dracula/gtk-4.0" ]; then
        mkdir -p "$TARGET_HOME/.config/gtk-4.0"
        cp -r "$THEMES_DIR/Dracula/gtk-4.0/"* "$TARGET_HOME/.config/gtk-4.0/" 2>/dev/null || true
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/gtk-4.0" 2>/dev/null || true
    fi

    # GTK 2 settings
    cat <<EOF >"$TARGET_HOME/.gtkrc-2.0"
gtk-theme-name="Dracula"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="JetBrains Mono 10"
gtk-cursor-theme-name="Dracula-cursors"
EOF
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.gtkrc-2.0" 2>/dev/null || true

    # System-wide GTK 3 fallback
    if [ -n "${SUDO:-}" ] || [ "$(id -u)" -eq 0 ]; then
        ${SUDO:-sudo} mkdir -p /etc/gtk-3.0
        cat <<EOF | ${SUDO:-sudo} tee /etc/gtk-3.0/settings.ini >/dev/null
[Settings]
gtk-theme-name=Dracula
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrains Mono 10
gtk-cursor-theme-name=Dracula-cursors
gtk-application-prefer-dark-theme=1
EOF
    fi

    # Default cursor theme
    mkdir -p "$TARGET_HOME/.icons/default"
    cat <<EOF >"$TARGET_HOME/.icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=Dracula-cursors
EOF
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.icons" 2>/dev/null || true

    # GNOME / Cinnamon / MATE / Budgie (gsettings)
    apply_gsettings() {
        local schema="$1" key="$2" val="$3"
        if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
            local u_uid
            u_uid="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
            sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${u_uid}/bus" \
                gsettings set "$schema" "$key" "$val" 2>/dev/null || true
        else
            gsettings set "$schema" "$key" "$val" 2>/dev/null || true
        fi
    }

    if command -v gsettings >/dev/null 2>&1; then
        apply_gsettings "org.gnome.desktop.interface" "gtk-theme" "Dracula"
        apply_gsettings "org.gnome.desktop.interface" "icon-theme" "Papirus-Dark"
        apply_gsettings "org.gnome.desktop.interface" "color-scheme" "prefer-dark"
        apply_gsettings "org.gnome.desktop.interface" "cursor-theme" "Dracula-cursors"
        apply_gsettings "org.gnome.desktop.interface" "font-name" "JetBrains Mono 10"
        apply_gsettings "org.gnome.desktop.interface" "monospace-font-name" "JetBrainsMono Nerd Font 10"
        apply_gsettings "org.gnome.desktop.wm.preferences" "theme" "Dracula"
    fi

    # XFCE (xfconf-query)
    apply_xfconf() {
        local channel="$1" prop="$2" val="$3"
        if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
            sudo -u "$TARGET_USER" xfconf-query -c "$channel" -p "$prop" -s "$val" 2>/dev/null || true
        else
            xfconf-query -c "$channel" -p "$prop" -s "$val" 2>/dev/null || true
        fi
    }

    if command -v xfconf-query >/dev/null 2>&1; then
        apply_xfconf "xsettings" "/Net/ThemeName" "Dracula"
        apply_xfconf "xsettings" "/Net/IconThemeName" "Papirus-Dark"
        apply_xfconf "xsettings" "/Gtk/CursorThemeName" "Dracula-cursors"
        apply_xfconf "xsettings" "/Gtk/FontName" "JetBrains Mono 10"
        apply_xfconf "xsettings" "/Gtk/MonospaceFontName" "JetBrainsMono Nerd Font 10"
        apply_xfconf "xfwm4" "/general/theme" "Dracula"
    fi

    # KDE Plasma (kwriteconfig for GTK / Icons)
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file "$TARGET_HOME/.config/kdeglobals" --group Icons --key Theme "Papirus-Dark" 2>/dev/null || true
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file "$TARGET_HOME/.config/kdeglobals" --group Icons --key Theme "Papirus-Dark" 2>/dev/null || true
    fi

    # nwg-look (tiling / wayland tool)
    if command -v nwg-look >/dev/null 2>&1; then
        if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
            sudo -u "$TARGET_USER" nwg-look -a 2>/dev/null || true
        else
            nwg-look -a 2>/dev/null || true
        fi
    fi

    # Refresh system font cache
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
    fi

    log "Theme applied successfully: Dracula GTK, Papirus-Dark icons, Dracula-cursors, and JetBrains Mono."
fi
