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

ui_ensure_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        ui_detect
        return 0
    fi

    # Never install packages during dry-run / simulation mode
    if is_simulate || [ "${DRY_RUN:-false}" = true ] || [ "${DRY_RUN_MODE:-false}" = true ]; then
        return 0
    fi

    printf '\033[0;34m[INFO]\033[0m "dialog" not found. Installing "dialog" for TUI...\n'

    if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; then
        pkg install -y dialog || true
        ui_detect
        if [ "$UI_TOOL" = "dialog" ]; then
            printf '\033[0;32m[OK]\033[0m Successfully installed dialog.\n'
            return 0
        fi
        if [ "$UI_TOOL" = "whiptail" ]; then
            printf '\033[1;33m[WARN]\033[0m Could not install dialog. Whiptail will be used as fallback.\n' >&2
            return 0
        fi
        return 1
    fi

    local sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            if ! sudo -v; then
                printf '\033[1;33m[WARN]\033[0m Sudo authentication failed; cannot auto-install dialog.\n' >&2
                ui_detect
                return 1
            fi
            sudo_cmd="sudo"
        elif command -v doas >/dev/null 2>&1; then
            sudo_cmd="doas"
        else
            printf '\033[1;33m[WARN]\033[0m Neither sudo nor doas found; cannot auto-install dialog.\n' >&2
            ui_detect
            return 1
        fi
    fi

    local distro="${TARGET_DISTRO:-}"
    if [ -z "$distro" ] || [ "$distro" = "unknown" ]; then
        if [ -f /etc/os-release ]; then
            local id_like id
            id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
            id_like="$(grep -E '^ID_LIKE=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
            case "$id" in
                arch | manjaro | endeavouros | garuda | artix | cachyos) distro="arch" ;;
                fedora | rhel | centos | rocky | almalinux | nobara) distro="fedora" ;;
                debian | ubuntu | pop | linuxmint | elementary | raspbian) distro="debian" ;;
                kali) distro="kali" ;;
                *)
                    for l in $id_like; do
                        case "$l" in
                            arch)
                                distro="arch"
                                break
                                ;;
                            fedora | rhel)
                                distro="fedora"
                                break
                                ;;
                            debian | ubuntu)
                                distro="debian"
                                break
                                ;;
                        esac
                    done
                    ;;
            esac
        fi
    fi

    case "$distro" in
        arch)
            $sudo_cmd pacman -S --needed --noconfirm dialog 2>/dev/null ||
                $sudo_cmd pacman -Sy --needed --noconfirm dialog || true
            ;;
        fedora)
            if command -v dnf5 >/dev/null 2>&1; then
                $sudo_cmd dnf5 install -y dialog || true
            else
                $sudo_cmd dnf install -y dialog || true
            fi
            ;;
        debian | kali)
            $sudo_cmd apt-get update -qq || true
            DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y dialog || true
            ;;
        termux)
            pkg install -y dialog || true
            ;;
        *)
            if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ] || command -v pkg >/dev/null 2>&1; then
                pkg install -y dialog || true
            elif command -v pacman >/dev/null 2>&1; then
                $sudo_cmd pacman -S --needed --noconfirm dialog 2>/dev/null ||
                    $sudo_cmd pacman -Sy --needed --noconfirm dialog || true
            elif command -v dnf5 >/dev/null 2>&1; then
                $sudo_cmd dnf5 install -y dialog || true
            elif command -v dnf >/dev/null 2>&1; then
                $sudo_cmd dnf install -y dialog || true
            elif command -v apt-get >/dev/null 2>&1; then
                $sudo_cmd apt-get update -qq || true
                DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y dialog || true
            elif command -v zypper >/dev/null 2>&1; then
                $sudo_cmd zypper --non-interactive install dialog || true
            elif command -v apk >/dev/null 2>&1; then
                $sudo_cmd apk add dialog || true
            fi
            ;;
    esac

    ui_detect
    if [ "$UI_TOOL" = "dialog" ]; then
        printf '\033[0;32m[OK]\033[0m Successfully installed dialog.\n'
        return 0
    fi

    if [ "$UI_TOOL" = "whiptail" ]; then
        printf '\033[1;33m[WARN]\033[0m Could not install dialog. Whiptail will be used as fallback.\n' >&2
        return 0
    fi

    printf '\033[1;33m[WARN]\033[0m Could not install dialog. Falling back to CLI mode.\n' >&2
    return 1
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

    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null || echo 24)
    term_cols=$(tput cols 2>/dev/null || echo 80)
    [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=24
    [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80

    local box_width=92
    if [ "$term_cols" -lt 98 ]; then
        box_width=$((term_cols - 6))
    fi
    [ "$box_width" -lt 76 ] && box_width=76

    local count=$((${#items[@]} / 2))
        local box_height=$((count + 8))
        local max_box=$((term_lines - 4))
        [ "$max_box" -lt 16 ] && max_box=16
        [ "$box_height" -gt "$max_box" ] && box_height="$max_box"
        [ "$box_height" -lt 16 ] && box_height=16

        local menu_height=$count
        local max_menu=$((box_height - 8))
        [ "$menu_height" -gt "$max_menu" ] && menu_height="$max_menu"
        [ "$menu_height" -lt 6 ] && menu_height=6

        case "$UI_TOOL" in
            whiptail)
                whiptail --default-item "$default_tag" --title "$title" --menu "$prompt" \
                    "$box_height" "$box_width" "$menu_height" "${items[@]}" 3>&1 1>&2 2>&3 </dev/tty
                ;;
            dialog)
                dialog --default-item "$default_tag" --no-hot-list --stdout --title "$title" --menu "$prompt" \
                    "$box_height" "$box_width" "$menu_height" "${items[@]}" </dev/tty
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
    local -a items=("$@")

    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null || echo 24)
    term_cols=$(tput cols 2>/dev/null || echo 80)
    [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=24
    [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80

    local box_width=92
    if [ "$term_cols" -lt 98 ]; then
        box_width=$((term_cols - 6))
    fi
    [ "$box_width" -lt 76 ] && box_width=76

    while true; do
        local -a display_items=(
            "ALL" "--> [Select All Components]" "OFF"
            "NONE" "--> [Deselect All Components]" "OFF"
        )
        display_items+=("${items[@]}")

        local count=$((${#display_items[@]} / 3))
            local box_height=$((count + 9))
            local max_box=$((term_lines - 4))
            [ "$max_box" -lt 16 ] && max_box=16
            [ "$box_height" -gt "$max_box" ] && box_height="$max_box"
            [ "$box_height" -lt 16 ] && box_height=16

            local list_height=$count
            local max_list=$((box_height - 7))
            [ "$list_height" -gt "$max_list" ] && list_height="$max_list"
            [ "$list_height" -lt 6 ] && list_height=6

            local raw=""
            case "$UI_TOOL" in
                whiptail)
                    raw=$(whiptail --title "$title" --checklist "$prompt" \
                        "$box_height" "$box_width" "$list_height" "${display_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return $?
                    ;;
                dialog)
                    raw=$(dialog --no-hot-list --stdout --title "$title" --checklist "$prompt" \
                        "$box_height" "$box_width" "$list_height" "${display_items[@]}" </dev/tty) || return $?
                    ;;
                *)
                    return 1
                    ;;
            esac

            local -a selected=()
            local line
            local has_all=false
            local has_none=false
            while IFS= read -r line; do
                line="${line//\"/}"
                line="${line// /}"
                [ -z "$line" ] && continue
                if [ "$line" = "ALL" ]; then
                    has_all=true
                elif [ "$line" = "NONE" ]; then
                    has_none=true
                else
                    selected+=("$line")
                fi
            done < <(printf '%s\n' "$raw" | tr ' ' '\n' | tr -d '"')

            if [ "$has_all" = true ]; then
                local i
                for ((i = 0; i < ${#items[@]}; i += 3)); do
                    items[i + 2]="ON"
                done
                continue
            fi

            if [ "$has_none" = true ]; then
                local i
                for ((i = 0; i < ${#items[@]}; i += 3)); do
                    items[i + 2]="OFF"
                done
                continue
            fi

            if [ ${#selected[@]} -gt 0 ]; then
                printf '%s\n' "${selected[@]}"
            fi
            return 0
        done
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
