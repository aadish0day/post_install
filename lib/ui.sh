#!/usr/bin/env bash
# TUI wrapper for dialog and whiptail.
# Provides standard dialog interfaces reading directly from /dev/tty.

UI_TOOL="${UI_TOOL:-none}"

ui_detect() {
    if command -v dialog >/dev/null 2>&1; then
        UI_TOOL="dialog"
    elif command -v whiptail >/dev/null 2>&1; then
        UI_TOOL="whiptail"
    else
        UI_TOOL="none"
    fi
    export UI_TOOL
}

ui_restore_cursor() {
    printf '\033[?25h\033[0 q' >/dev/tty 2>/dev/null || tput cnorm 2>/dev/null || true
}

setup_vim_keybindings() {
    local rc_file="${TMPDIR:-/tmp}/.dialogrc_post_install_$$"
    cat <<'RC' >"$rc_file"
use_shadow = ON
use_colors = ON

# Input box high-contrast styling: bold white text on blue background prevents invisible cursor on dark terminals
inputbox_color = (WHITE,BLUE,ON)
inputbox_border_color = (CYAN,BLUE,ON)
inputbox_border2_color = (CYAN,BLUE,ON)

# Checklist navigation: j (\152), k (\153), g (\147), G (\107), h (\150), l (\154)
bindkey checklist \152 ITEM_NEXT
bindkey checklist \153 ITEM_PREV
bindkey checklist \147 PAGE_FIRST
bindkey checklist \107 PAGE_LAST
bindkey checklist \150 FIELD_PREV
bindkey checklist \154 FIELD_NEXT

# Menu navigation
bindkey menu \152 ITEM_NEXT
bindkey menu \153 ITEM_PREV
bindkey menu \147 PAGE_FIRST
bindkey menu \107 PAGE_LAST
bindkey menu \150 FIELD_PREV
bindkey menu \154 FIELD_NEXT

# Menubox navigation
bindkey menubox \152 ITEM_NEXT
bindkey menubox \153 ITEM_PREV
bindkey menubox \147 PAGE_FIRST
bindkey menubox \107 PAGE_LAST
bindkey menubox \150 FIELD_PREV
bindkey menubox \154 FIELD_NEXT

# Msgbox navigation
bindkey msgbox \150 FIELD_PREV
bindkey msgbox \154 FIELD_NEXT
bindkey msgbox \152 FIELD_NEXT
bindkey msgbox \153 FIELD_PREV

# YesNo navigation
bindkey yesno \150 FIELD_PREV
bindkey yesno \154 FIELD_NEXT
bindkey yesno \152 FIELD_NEXT
bindkey yesno \153 FIELD_PREV
RC
    export DIALOGRC="$rc_file"
}

ui_init() {
    if [ "$UI_TOOL" = "dialog" ]; then
        setup_vim_keybindings
    fi
}

ui_menu() {
    local title="$1"
    local prompt="$2"
    local default_tag="$3"
    shift 3
    local items=("$@")

    local count=$(( ${#items[@]} / 2 ))
    local box_height=$(( count + 8 ))
    [ "$box_height" -lt 14 ] && box_height=14
    [ "$box_height" -gt 22 ] && box_height=22
    local menu_height=$count
    [ "$menu_height" -gt 14 ] && menu_height=14

    case "$UI_TOOL" in
    whiptail)
        whiptail --default-item "$default_tag" --title "$title" --menu "$prompt" \
            "$box_height" 84 "$menu_height" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty
        ;;
    dialog)
        dialog --default-item "$default_tag" --no-hot-list --stdout --title "$title" --menu "$prompt" \
            "$box_height" 84 "$menu_height" "${items[@]}" </dev/tty
        ;;
    *)
        return 1
        ;;
    esac
}

ui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    local count=$(( ${#items[@]} / 3 ))
    local box_height=$(( count + 8 ))
    [ "$box_height" -lt 14 ] && box_height=14
    [ "$box_height" -gt 24 ] && box_height=24
    local list_height=$count
    [ "$list_height" -gt 16 ] && list_height=16

    local raw=""
    case "$UI_TOOL" in
    whiptail)
        raw=$(whiptail --title "$title" --checklist "$prompt" \
            "$box_height" 80 "$list_height" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return $?
        ;;
    dialog)
        raw=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" \
            "$box_height" 80 "$list_height" "${items[@]}" </dev/tty) || return $?
        ;;
    *)
        return 1
        ;;
    esac

    # Normalize output: strip quotes, output one tag per line
    if [ -n "$raw" ]; then
        printf '%s\n' "$raw" | tr ' ' '\n' | tr -d '"' | sed '/^$/d'
    fi
    return 0
}

ui_yesno() {
    local title="$1"
    local prompt="$2"

    case "$UI_TOOL" in
    whiptail)
        whiptail --title "$title" --yesno "$prompt" 14 72 3>&1 1>&2 2>&3 </dev/tty
        ;;
    dialog)
        dialog --title "$title" --yesno "$prompt" 14 72 </dev/tty
        ;;
    *)
        return 1
        ;;
    esac
}

ui_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    case "$UI_TOOL" in
    whiptail)
        whiptail --title "$title" --inputbox "$prompt" 10 64 "$default" 3>&1 1>&2 2>&3 </dev/tty
        ;;
    dialog)
        dialog --stdout --title "$title" --inputbox "$prompt" 10 64 "$default" </dev/tty
        ;;
    *)
        return 1
        ;;
    esac
}

ui_msg() {
    local title="$1"
    local text="$2"

    case "$UI_TOOL" in
    whiptail)
        whiptail --title "$title" --msgbox "$text" 16 72 </dev/tty || true
        ;;
    dialog)
        dialog --title "$title" --msgbox "$text" 16 72 </dev/tty || true
        ;;
    *)
        printf '%s\n\n%s\n' "$title" "$text"
        ;;
    esac
}
