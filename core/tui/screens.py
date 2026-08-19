#!/usr/bin/env python3
"""
Interactive Screen implementations for the Archinstall-style TUI.
Provides GlobalMenuScreen, OptionListScreen, SelectListScreen, InputScreen, ConfirmScreen, and ExecutionScreen
with full Vim keybindings navigation (h/j/k/l, g/G, Ctrl+d/u, Space/x).
"""

from __future__ import annotations

import curses
import os
import queue
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from core.config import PostInstallConfig
from core.detector import SystemInfo, detect_system
from core.runner import ExecutionEvent, ExecutionPlan, StepStatus, run_plan
from core.tui.colors import Colors
from core.tui.widgets import draw_box, draw_footer, draw_header, safe_addstr


@dataclass
class MenuItem:
    key: str
    label: str
    value_display: str
    description: str
    preview_lines: List[str] = field(default_factory=list)
    action_type: str = "custom"
    is_action: bool = False


class GlobalMenuScreen:
    """The central Archinstall-style configuration menu screen."""

    def __init__(self, stdscr: curses.window, config: PostInstallConfig, sysinfo: SystemInfo):
        self.stdscr = stdscr
        self.config = config
        self.sysinfo = sysinfo
        self.cursor_idx = 0
        self.scroll_offset = 0

    def _build_menu_items(self) -> List[MenuItem]:
        cfg = self.config
        info = self.sysinfo
        distro = cfg.distro
        items: List[MenuItem] = []

        # 1. Distribution
        items.append(MenuItem(
            key="distro",
            label="Distribution / Target OS",
            value_display=f"[{distro.upper()}] {cfg.distro_name}",
            description="Active distribution workspace folder.",
            preview_lines=[
                f"Active OS Folder: ./{distro}/",
                f"Target OS:        {cfg.distro_name}",
                f"Detected System:  {info.distro_name} ({info.distro_id})",
                f"Host CPU:         {info.cpu_model or info.cpu_vendor.upper()}",
                f"Host GPU:         {', '.join(info.gpu_descriptions) if info.gpu_descriptions else 'Generic'}",
                "",
                "When on Arch, the installer executes ONLY modular scripts from arch/:",
                " • arch/arch.sh",
                " • arch/desktop/kde.sh & arch/desktop/tiling.sh",
                " • arch/hardware/asus.sh & arch/hardware/touchpad.sh",
                " • arch/virt/kvm-qemu.sh & arch/virt/vmware-workstation.sh",
                " • arch/apps/docker.sh",
                " • arch/apps/burp/install.sh"
            ],
            action_type="radio"
        ))

        # ==========================================================
        # ARCH LINUX SPECIFIC MENU ITEMS (STRICTLY arch/ CONTENT)
        # ==========================================================
        if distro == "arch":
            # 2. Desktop Environment (arch/desktop/kde.sh or arch/desktop/tiling.sh)
            de_map = {"kde": "KDE Plasma (arch/desktop/kde.sh)", "tiling": "X11 Tiling (arch/desktop/tiling.sh)", "none": "None (Skip Desktop)"}
            de_label = de_map.get(cfg.desktop_environment, "None")
            items.append(MenuItem(
                key="desktop_environment",
                label="Desktop Environment",
                value_display=f"[{cfg.desktop_environment.upper()}]",
                description="KDE Plasma or X11 Tiling setup from arch/desktop/.",
                preview_lines=[
                    f"Current selection: {de_label}",
                    "",
                    "Modular scripts in arch/desktop/:",
                    " • KDE Plasma (arch/desktop/kde.sh):",
                    "   Plasma desktop, Wayland/X11 sessions, Dolphin, Kate, Konsole, Ark, KDE Connect, portal services",
                    "",
                    " • X11 Tiling (arch/desktop/tiling.sh):",
                    "   Polybar, Picom compositor, Rofi, Dunst, Feh, Zathura, i3lock-color, Dracula GTK,",
                    "   and Precision Touchpad configuration (arch/hardware/touchpad.sh)",
                    "",
                    " • None:",
                    "   Skip desktop environment setup"
                ],
                action_type="radio"
            ))

            # 3. Hardware Drivers (arch/hardware/asus.sh & AMD GPU)
            hw_tags = []
            if cfg.hardware_asus:
                hw_tags.append(f"ASUS ROG ({cfg.hardware_asus_battery_limit}%)")
            if cfg.hardware_amd_gpu:
                hw_tags.append("AMD GPU")
            hw_display = ", ".join(hw_tags) if hw_tags else "[None]"

            items.append(MenuItem(
                key="hardware",
                label="Hardware & Drivers (arch/hardware/)",
                value_display=f"[{hw_display}]",
                description="ASUS ROG tools and AMD GPU acceleration.",
                preview_lines=[
                    f"Detected Chassis: {info.chassis_model or 'Generic'} (ASUS: {info.is_asus})",
                    f"Detected GPU:     {', '.join(info.gpu_descriptions) if info.gpu_descriptions else 'Generic'}",
                    "",
                    "Modular scripts in arch/hardware/:",
                    f" • ASUS ROG (arch/hardware/asus.sh): {'[Yes] asusctl, fan curves, ' + str(cfg.hardware_asus_battery_limit) + '% limit' if cfg.hardware_asus else '[No]'}",
                    f" • AMD GPU Drivers: {'[Yes] Mesa, Vulkan-Radeon, amd_pstate GRUB' if cfg.hardware_amd_gpu else '[No]'}"
                ],
                action_type="multiselect"
            ))

            # 4. Virtualization (arch/virt/kvm-qemu.sh & vmware-workstation.sh)
            virt_tags = []
            if cfg.virt_kvm_qemu:
                virt_tags.append("KVM/QEMU")
            if cfg.virt_vmware_workstation:
                virt_tags.append("VMware Host")
            virt_display = ", ".join(virt_tags) if virt_tags else "[None]"

            items.append(MenuItem(
                key="virtualization",
                label="Virtualization (arch/virt/)",
                value_display=f"[{virt_display}]",
                description="KVM/QEMU virt-manager and VMware Workstation.",
                preview_lines=[
                    "Modular scripts in arch/virt/:",
                    f" • KVM/QEMU (arch/virt/kvm-qemu.sh): {'[Yes] virt-manager, libvirtd bridge network' if cfg.virt_kvm_qemu else '[No]'}",
                    f" • VMware Workstation (arch/virt/vmware-workstation.sh): {'[Yes] AUR build & kernel modules' if cfg.virt_vmware_workstation else '[No]'}"
                ],
                action_type="multiselect"
            ))

            # 5. Docker (arch/apps/docker.sh)
            items.append(MenuItem(
                key="docker_enabled",
                label="Docker CE (arch/apps/docker.sh)",
                value_display="[Yes]" if cfg.docker_enabled else "[No]",
                description="Docker Engine, Compose plugin, Buildx, and user group permissions.",
                preview_lines=[
                    "Script: arch/apps/docker.sh",
                    f"Status: {'Yes' if cfg.docker_enabled else 'No'}",
                    "",
                    "Configures:",
                    " • docker, docker-compose, docker-buildx",
                    f" • sudo usermod -aG docker {info.username}",
                    " • sudo systemctl enable --now docker.service"
                ],
                action_type="toggle"
            ))

            # 6. Coding Tools (from arch/arch.sh aur_coding_packages)
            code_display = f"[{len(cfg.coding_tools)} tools]" if cfg.coding_enabled else "[No]"
            items.append(MenuItem(
                key="coding",
                label="Developer Tools (AUR)",
                value_display=code_display,
                description="VS Code, Cursor, Android Studio, Flutter, and Antigravity.",
                preview_lines=[
                    "Packages from arch/arch.sh (aur_coding_packages):",
                    f" • Active: {', '.join(cfg.coding_tools) if cfg.coding_tools else 'None'}",
                    "",
                    "Available AUR Packages:",
                    " • visual-studio-code-bin",
                    " • cursor-bin",
                    " • android-studio",
                    " • flutter-bin",
                    " • antigravity-cli & antigravity-ide"
                ],
                action_type="multiselect"
            ))

            # 7. Burp Suite Pro (arch/apps/burp/install.sh)
            items.append(MenuItem(
                key="security_burp",
                label="Burp Suite Pro (arch/apps/burp/)",
                value_display="[Yes]" if cfg.security_burp else "[No]",
                description="OpenJDK 21, auto-download latest JAR via aria2c, launcher script, desktop entry.",
                preview_lines=[
                    "Script: arch/apps/burp/install.sh",
                    f"Status: {'Yes' if cfg.security_burp else 'No'}",
                    "",
                    "Workflow:",
                    " • Installs jdk21-openjdk, git, aria2",
                    " • Clones Burpsuite loader and downloads latest release JAR",
                    " • Creates launcher binary: ~/.local/bin/burpsuitepro",
                    " • Creates desktop entry: ~/.local/share/applications/burpsuitepro.desktop"
                ],
                action_type="toggle"
            ))

            # 8. Gaming Stack (from arch/apps/gaming.sh)
            items.append(MenuItem(
                key="gaming_enabled",
                label="Gaming Stack & Wine",
                value_display="[Yes]" if cfg.gaming_enabled else "[No]",
                description="Wine-staging, Lutris, GameMode, Proton DXVK, and 32-bit graphics runtimes.",
                preview_lines=[
                    "Packages from arch/apps/gaming.sh:",
                    f"Status: {'Yes' if cfg.gaming_enabled else 'No'}",
                    "",
                    "Includes:",
                    " • wine-staging, winetricks, wine-mono, wine-gecko, lutris, gamemode, umu-launcher",
                    " • dxvk-gplasync-bin, lib32-vulkan-radeon, lib32-mesa"
                ],
                action_type="toggle"
            ))

            # 9. AI / ML ROCm Stack (from arch/arch.sh ai_ml_packages)
            items.append(MenuItem(
                key="ai_ml_enabled",
                label="AI / ML Acceleration (ROCm)",
                value_display="[Yes]" if cfg.ai_ml_enabled else "[No]",
                description="AMD ROCm SDK, PyTorch ROCm, and ONNX Runtime ROCm.",
                preview_lines=[
                    "Packages from arch/arch.sh (ai_ml_packages):",
                    f"Status: {'Yes' if cfg.ai_ml_enabled else 'No'}",
                    "",
                    "Includes:",
                    " • rocm-hip-sdk, rocm-opencl-sdk, rocm-ml-libraries",
                    " • python-pytorch-rocm, python-onnxruntime-rocm"
                ],
                action_type="toggle"
            ))

            # 10. AUR Helper Selection (arch/apps/paru.sh & arch/apps/yay.sh)
            aur_map = {
                "paru": "Paru (Rust, Recommended)",
                "yay": "Yay (Go)",
                "both": "Both (Paru + Yay)"
            }
            items.append(MenuItem(
                key="aur_helper",
                label="AUR Helper Selection",
                value_display=f"[{cfg.aur_helper.upper()}]",
                description="Select which AUR helper to install (Paru, Yay, or Both).",
                preview_lines=[
                    f"Active Helper: {aur_map.get(cfg.aur_helper, cfg.aur_helper.upper())}",
                    "",
                    "Modular Scripts in arch/apps/:",
                    " • Paru (arch/apps/paru.sh):",
                    "   Modern Rust-based AUR helper with fast paru-bin support.",
                    "",
                    " • Yay (arch/apps/yay.sh):",
                    "   Classic Go-based AUR helper with fast yay-bin support.",
                    "",
                    " • Both (Paru + Yay):",
                    "   Installs both Paru and Yay side-by-side."
                ],
                action_type="radio"
            ))

            # 11. Mirror Optimization (Reflector India)
            items.append(MenuItem(
                key="repos_mirror_ranking",
                label="Mirror Optimization (Reflector India)",
                value_display="[Yes]" if cfg.repos_mirror_ranking else "[No]",
                description="Ranks the fastest HTTPS mirrors strictly in India with 30s timeout.",
                preview_lines=[
                    "Configuration: arch/arch.sh & Reflector",
                    f"Status: {'Yes (Strictly India mirrors)' if cfg.repos_mirror_ranking else 'No'}",
                    "",
                    "Command:",
                    "sudo reflector --country India --latest 10 --fastest 5 --sort rate --save /etc/pacman.d/mirrorlist"
                ],
                action_type="toggle"
            ))

        # ==========================================================
        # KALI LINUX SPECIFIC MENU ITEMS (STRICTLY kali/ CONTENT)
        # ==========================================================
        elif distro == "kali":
            items.append(MenuItem(
                key="security_burp",
                label="Burp Suite Pro (kali/apps/burp/)",
                value_display="[Yes]" if cfg.security_burp else "[No]",
                description="Burp Suite Professional installer from kali/apps/burp/install.sh.",
                preview_lines=["Script: kali/apps/burp/install.sh", f"Status: {'Yes' if cfg.security_burp else 'No'}"],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="kali_metapackages",
                label="Kali Metapackages",
                value_display=f"[{', '.join(cfg.security_kali_metapackages) if cfg.security_kali_metapackages else 'None'}]",
                description="kali-linux-everything, kali-linux-large, kali-linux-labs.",
                preview_lines=[f"Active suites: {', '.join(cfg.security_kali_metapackages)}"],
                action_type="multiselect"
            ))
            items.append(MenuItem(
                key="hardware_kali_wifi",
                label="WiFi Driver (kali/hardware/wifi.sh)",
                value_display="[Yes]" if cfg.hardware_kali_wifi else "[No]",
                description="Realtek 8821AU USB WiFi DKMS driver.",
                preview_lines=["Script: kali/hardware/wifi.sh"],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="docker_enabled",
                label="Docker CE (kali/apps/docker.sh)",
                value_display="[Yes]" if cfg.docker_enabled else "[No]",
                description="Docker CE engine configured for Kali.",
                preview_lines=["Script: kali/apps/docker.sh"],
                action_type="toggle"
            ))

        # ==========================================================
        # DEBIAN / UBUNTU MENU ITEMS (STRICTLY debian/ CONTENT)
        # ==========================================================
        elif distro == "debian":
            items.append(MenuItem(
                key="debian_neovim",
                label="Neovim Source (debian/apps/neovim.sh)",
                value_display="[Yes]" if "neovim" in cfg.coding_tools else "[No]",
                description="Compiles latest Neovim from source.",
                preview_lines=["Script: debian/apps/neovim.sh"],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="docker_enabled",
                label="Docker CE (debian/apps/docker.sh)",
                value_display="[Yes]" if cfg.docker_enabled else "[No]",
                description="Official Docker CE repository & engine.",
                preview_lines=["Script: debian/apps/docker.sh"],
                action_type="toggle"
            ))

        # ==========================================================
        # FEDORA MENU ITEMS (STRICTLY fedora/ CONTENT)
        # ==========================================================
        elif distro == "fedora":
            items.append(MenuItem(
                key="fedora_core",
                label="Fedora Setup (fedora/fedora.sh)",
                value_display="[Yes]",
                description="DNF optimizations, RPM Fusion, and COPR repos.",
                preview_lines=["Script: fedora/fedora.sh", "Config: fedora/config/dnf.conf"],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="docker_enabled",
                label="Docker CE (fedora/apps/docker.sh)",
                value_display="[Yes]" if cfg.docker_enabled else "[No]",
                description="Official Docker CE engine for Fedora.",
                preview_lines=["Script: fedora/apps/docker.sh"],
                action_type="toggle"
            ))

        # ==========================================================
        # TERMUX MENU ITEMS (STRICTLY termux/ CONTENT)
        # ==========================================================
        elif distro == "termux":
            items.append(MenuItem(
                key="termux_core",
                label="Termux Setup (termux/termux.sh)",
                value_display="[Yes]",
                description="Termux storage, zsh, tmux, python, and dotfiles.",
                preview_lines=["Script: termux/termux.sh"],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="termux_font",
                label="Nerd Font (termux/system/font.sh)",
                value_display="[Yes]" if cfg.theme_nerd_fonts else "[No]",
                description="JetBrains Mono Nerd Font for Termux.",
                preview_lines=["Script: termux/system/font.sh"],
                action_type="toggle"
            ))

        # ==========================================================
        # ACTION BUTTONS AT BOTTOM
        # ==========================================================
        items.append(MenuItem(
            key="action_install",
            label="▶ Install",
            value_display="[Start post-installation]",
            description=f"Execute the post-installation plan using ./{distro}/ modular scripts.",
            preview_lines=[
                "========================================",
                f"   READY TO RUN ./{distro.upper()}/ POST-INSTALL",
                "========================================",
                f"Target OS: {cfg.distro_name}",
                "",
                "Press ENTER or 'l' to review planned steps",
                "and execute the automated installer."
            ],
            action_type="action",
            is_action=True
        ))

        items.append(MenuItem(
            key="action_save",
            label="💾 Save Configuration",
            value_display="[Save to JSON]",
            description="Export all configured options to a JSON profile.",
            preview_lines=["Save your current settings to a JSON profile."],
            action_type="action",
            is_action=True
        ))

        items.append(MenuItem(
            key="action_load",
            label="📂 Load Configuration",
            value_display="[Load from JSON]",
            description="Import a previously saved JSON configuration file.",
            preview_lines=["Import settings from a local JSON file."],
            action_type="action",
            is_action=True
        ))

        items.append(MenuItem(
            key="action_abort",
            label="✖ Abort",
            value_display="[Exit installer]",
            description="Exit without applying changes.",
            preview_lines=["Exit the post-installation suite."],
            action_type="action",
            is_action=True
        ))

        return items

    def run(self) -> Optional[str]:
        """Main event loop for the Global Menu with full Vim keybinding support."""
        curses.curs_set(0)
        self.stdscr.keypad(True)
        self.stdscr.nodelay(False)

        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()

            if max_y < 16 or max_x < 60:
                safe_addstr(self.stdscr, 1, 1, "Terminal window is too small.", Colors.warning())
                safe_addstr(self.stdscr, 2, 1, f"Please resize to at least 80x24 (Current: {max_x}x{max_y}).", Colors.dim())
                safe_addstr(self.stdscr, 4, 1, "Press 'q' to exit.", Colors.normal())
                self.stdscr.refresh()
                ch = self.stdscr.getch()
                if ch in (ord('q'), ord('Q'), 27):
                    return "exit"
                continue

            items = self._build_menu_items()
            total_items = len(items)
            self.cursor_idx = max(0, min(self.cursor_idx, total_items - 1))

            # Header
            sub_info = f"Host: {self.sysinfo.hostname} ({self.sysinfo.cpu_vendor.upper()}) | OS Folder: ./{self.config.distro}/ | User: {self.sysinfo.username}"
            draw_header(self.stdscr, f"{self.config.distro_name.upper()} POST-INSTALLATION SUITE", sub_info)

            # Footer with Vim keybindings indicator
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [g/G] Top/Bottom  [Ctrl+d/u] Scroll  [Enter/l] Open  [Space/x] Toggle  [s] Save  [o] Load  [Esc/q] Exit ")

            # Calculate box dimensions
            content_top = 3
            content_bottom = max_y - 2
            available_h = content_bottom - content_top + 1

            split_mode = max_x >= 90
            if split_mode:
                menu_w = int(max_x * 0.54)
                preview_w = max_x - menu_w - 2
                menu_x = 1
                preview_x = menu_w + 2
                menu_h = available_h
                preview_h = available_h
            else:
                menu_w = max_x - 2
                preview_w = max_x - 2
                menu_x = 1
                preview_x = 1
                menu_h = max(8, int(available_h * 0.6))
                preview_h = available_h - menu_h

            # Draw Menu Box
            draw_box(self.stdscr, content_top, menu_x, menu_h, menu_w, f"Configuration Menu [{self.config.distro.upper()}]", Colors.primary(bold=True))

            # Adjust scroll
            visible_rows = menu_h - 2
            if self.cursor_idx < self.scroll_offset:
                self.scroll_offset = self.cursor_idx
            elif self.cursor_idx >= self.scroll_offset + visible_rows:
                self.scroll_offset = self.cursor_idx - visible_rows + 1

            # Render menu items
            for i in range(visible_rows):
                item_idx = self.scroll_offset + i
                if item_idx >= total_items:
                    break

                item = items[item_idx]
                row_y = content_top + 1 + i
                is_selected = (item_idx == self.cursor_idx)

                prefix = " > " if is_selected else "   "
                lbl = item.label
                val = item.value_display

                avail_txt_w = menu_w - 4
                lbl_len = len(lbl)
                val_len = len(val)

                if is_selected:
                    # Highlight active row in bold white on blue
                    if lbl_len + val_len + 4 <= avail_txt_w:
                        spaces = " " * (avail_txt_w - lbl_len - val_len - 3)
                        full_line = f"{prefix}{lbl}{spaces}{val}"
                    else:
                        truncated_lbl = lbl[:max(8, avail_txt_w - val_len - 6)] + ".."
                        spaces = " " * max(1, avail_txt_w - len(truncated_lbl) - val_len - 3)
                        full_line = f"{prefix}{truncated_lbl}{spaces}{val}"
                    safe_addstr(self.stdscr, row_y, menu_x + 1, full_line.ljust(menu_w - 2), Colors.highlight(bold=True))
                else:
                    # Clear row background
                    safe_addstr(self.stdscr, row_y, menu_x + 1, " " * (menu_w - 2), Colors.normal())

                    # Draw label on the left
                    lbl_attr = Colors.accent(bold=True) if item.is_action else Colors.normal()
                    max_lbl_w = max(10, avail_txt_w - val_len - 4)
                    display_lbl = lbl if len(lbl) <= max_lbl_w else lbl[:max_lbl_w - 2] + ".."
                    safe_addstr(self.stdscr, row_y, menu_x + 1, f"{prefix}{display_lbl}", lbl_attr)

                    # Determine color for the value tag on the right
                    if val == "[Yes]":
                        val_attr = Colors.success(bold=True)
                    elif val == "[No]":
                        val_attr = Colors.error(bold=True)
                    elif val.startswith("[") and val.endswith("]"):
                        val_attr = Colors.primary(bold=True)
                    else:
                        val_attr = Colors.normal()

                    val_x = menu_x + menu_w - 1 - val_len - 1
                    safe_addstr(self.stdscr, row_y, val_x, val, val_attr)

            # Draw Preview Box
            selected_item = items[self.cursor_idx]
            prev_y = content_top if split_mode else content_top + menu_h
            draw_box(self.stdscr, prev_y, preview_x, preview_h, preview_w, "Item Details & Preview", Colors.primary(bold=True))

            safe_addstr(self.stdscr, prev_y + 1, preview_x + 2, f"Option: {selected_item.label}", Colors.primary(bold=True))
            safe_addstr(self.stdscr, prev_y + 2, preview_x + 2, selected_item.description, Colors.dim())
            safe_addstr(self.stdscr, prev_y + 3, preview_x + 2, "─" * (preview_w - 4), Colors.dim())

            prev_visible_rows = preview_h - 5
            for p_i, line in enumerate(selected_item.preview_lines[:prev_visible_rows]):
                p_attr = Colors.normal()
                if "[Yes]" in line or line.startswith("Status: Yes"):
                    p_attr = Colors.success(bold=True)
                elif "[No]" in line or line.startswith("Status: No"):
                    p_attr = Colors.error(bold=True)
                elif line.startswith("==") or line.startswith("Active") or line.startswith("Modular") or line.startswith("Available"):
                    p_attr = Colors.accent(bold=True)
                elif line.startswith(" •"):
                    p_attr = Colors.primary(bold=False)
                safe_addstr(self.stdscr, prev_y + 4 + p_i, preview_x + 2, line, p_attr)

            self.stdscr.refresh()

            # Handle Keys (with Full Vim Keybindings)
            key = self.stdscr.getch()

            # Navigation: Down (j / Down Arrow)
            if key in (curses.KEY_DOWN, ord('j'), ord('J')):
                self.cursor_idx = (self.cursor_idx + 1) % total_items

            # Navigation: Up (k / Up Arrow)
            elif key in (curses.KEY_UP, ord('k'), ord('K')):
                self.cursor_idx = (self.cursor_idx - 1) % total_items

            # Jump to top: g / Home
            elif key in (curses.KEY_HOME, ord('g')):
                self.cursor_idx = 0

            # Jump to bottom: G / End
            elif key in (curses.KEY_END, ord('G')):
                self.cursor_idx = total_items - 1

            # Half-page down: Ctrl+d (4) / Page Down (curses.KEY_NPAGE) / Ctrl+f (6)
            elif key in (4, 6, curses.KEY_NPAGE):
                self.cursor_idx = min(total_items - 1, self.cursor_idx + max(1, visible_rows // 2))

            # Half-page up: Ctrl+u (21) / Page Up (curses.KEY_PPAGE) / Ctrl+b (2)
            elif key in (21, 2, curses.KEY_PPAGE):
                self.cursor_idx = max(0, self.cursor_idx - max(1, visible_rows // 2))

            # Toggle Boolean / Quick Checkmark: Space or x
            elif key in (ord(' '), ord('x'), ord('X')):
                cur_key = selected_item.key
                if cur_key == "docker_enabled":
                    self.config.docker_enabled = not self.config.docker_enabled
                elif cur_key == "security_burp":
                    self.config.security_burp = not self.config.security_burp
                elif cur_key == "gaming_enabled":
                    self.config.gaming_enabled = not self.config.gaming_enabled
                elif cur_key == "ai_ml_enabled":
                    self.config.ai_ml_enabled = not self.config.ai_ml_enabled
                elif cur_key == "hardware_kali_wifi":
                    self.config.hardware_kali_wifi = not self.config.hardware_kali_wifi

            # Select / Open Submenu: Enter or l (Vim forward) or Right Arrow
            elif key in (10, 13, curses.KEY_ENTER, ord('l'), curses.KEY_RIGHT):
                action_res = self._handle_item_select(selected_item)
                if action_res == "install":
                    return "install"
                elif action_res == "exit":
                    return "exit"

            # Save Config: s / S
            elif key in (ord('s'), ord('S')):
                self._save_config_prompt()

            # Load Config: o / O
            elif key in (ord('o'), ord('O')):
                self._load_config_prompt()

            # Exit / Back: Esc / q / Q
            elif key in (ord('q'), ord('Q'), 27):
                confirm = ConfirmScreen(self.stdscr, "Exit Installer?", "Are you sure you want to exit without applying changes?").run()
                if confirm:
                    return "exit"

    def _handle_item_select(self, item: MenuItem) -> Optional[str]:
        k = item.key

        if k == "action_install":
            return "install"
        elif k == "action_save":
            self._save_config_prompt()
        elif k == "action_load":
            self._load_config_prompt()
        elif k == "action_abort":
            confirm = ConfirmScreen(self.stdscr, "Exit Installer?", "Are you sure you want to exit without applying changes?").run()
            if confirm:
                return "exit"

        elif k == "distro":
            options = [
                ("arch", "Arch Linux (arch/ modular folder)"),
                ("debian", "Debian / Ubuntu (debian/ modular folder)"),
                ("fedora", "Fedora (fedora/ modular folder)"),
                ("kali", "Kali Linux (kali/ modular folder)"),
                ("termux", "Termux (termux/ modular folder)")
            ]
            sel = OptionListScreen(self.stdscr, "Select Active Distribution Folder", options, self.config.distro).run()
            if sel:
                self.config.set_distro(sel)

        elif k == "desktop_environment":
            options = [
                ("kde", "KDE Plasma (arch/desktop/kde.sh)"),
                ("tiling", "X11 Tiling Window Manager (arch/desktop/tiling.sh)"),
                ("none", "None / Headless (Skip desktop environment setup)")
            ]
            sel = OptionListScreen(self.stdscr, "Select Desktop Environment (arch/desktop/)", options, self.config.desktop_environment).run()
            if sel:
                self.config.desktop_environment = sel

        elif k == "hardware":
            options = [
                ("asus", "ASUS ROG Tools & Fan Curves (arch/hardware/asus.sh)", self.config.hardware_asus),
                ("amd", "AMD GPU Drivers & Kernel Optimization (Mesa, Vulkan, GRUB)", self.config.hardware_amd_gpu)
            ]
            res = SelectListScreen(self.stdscr, "Hardware & Drivers (arch/hardware/)", options).run()
            if res is not None:
                self.config.hardware_asus = "asus" in res
                self.config.hardware_amd_gpu = "amd" in res

                if self.config.hardware_asus:
                    limit_str = InputScreen(self.stdscr, "ASUS Battery Limit", "Enter battery charge threshold percentage (50-100):", str(self.config.hardware_asus_battery_limit)).run()
                    if limit_str and limit_str.isdigit():
                        self.config.hardware_asus_battery_limit = max(50, min(100, int(limit_str)))

        elif k == "virtualization":
            options = [
                ("kvm", "KVM / QEMU & virt-manager (arch/virt/kvm-qemu.sh)", self.config.virt_kvm_qemu),
                ("vmware_host", "VMware Workstation Host (arch/virt/vmware-workstation.sh)", self.config.virt_vmware_workstation)
            ]
            res = SelectListScreen(self.stdscr, "Virtualization Setup (arch/virt/)", options).run()
            if res is not None:
                self.config.virt_kvm_qemu = "kvm" in res
                self.config.virt_vmware_workstation = "vmware_host" in res

        elif k == "docker_enabled":
            self.config.docker_enabled = not self.config.docker_enabled

        elif k == "coding":
            options = [
                ("vscode", "Visual Studio Code (visual-studio-code-bin)", "vscode" in self.config.coding_tools),
                ("cursor", "Cursor AI Code Editor (cursor-bin)", "cursor" in self.config.coding_tools),
                ("android_studio", "Android Studio (android-studio)", "android_studio" in self.config.coding_tools),
                ("flutter", "Flutter SDK (flutter-bin)", "flutter" in self.config.coding_tools),
                ("antigravity", "Antigravity CLI & IDE", "antigravity" in self.config.coding_tools)
            ]
            res = SelectListScreen(self.stdscr, "Developer & Coding Stack (arch/arch.sh aur_coding_packages)", options).run()
            if res is not None:
                self.config.coding_tools = res
                self.config.coding_enabled = len(res) > 0

        elif k == "security_burp":
            self.config.security_burp = not self.config.security_burp

        elif k == "gaming_enabled":
            self.config.gaming_enabled = not self.config.gaming_enabled

        elif k == "ai_ml_enabled":
            self.config.ai_ml_enabled = not self.config.ai_ml_enabled

        elif k == "aur_helper":
            options = [
                ("paru", "Paru (Rust, fast, feature-rich - Recommended)"),
                ("yay", "Yay (Go, classic Arch AUR helper)"),
                ("both", "Both (Install both Paru and Yay)")
            ]
            sel = OptionListScreen(self.stdscr, "Select AUR Helper (arch/apps/)", options, self.config.aur_helper).run()
            if sel:
                self.config.aur_helper = sel
                self.config.repos_aur_paru = True

        elif k == "repos_mirror_ranking":
            self.config.repos_mirror_ranking = not self.config.repos_mirror_ranking

        elif k == "kali_metapackages":
            options = [
                ("everything", "kali-linux-everything (All Kali tools, ~10GB+)", "everything" in self.config.security_kali_metapackages),
                ("large", "kali-linux-large (Extended default toolset)", "large" in self.config.security_kali_metapackages),
                ("labs", "kali-linux-labs (Vulnerable testing environments)", "labs" in self.config.security_kali_metapackages)
            ]
            res = SelectListScreen(self.stdscr, "Kali Linux Metapackages", options).run()
            if res is not None:
                self.config.security_kali_metapackages = res

        elif k == "hardware_kali_wifi":
            self.config.hardware_kali_wifi = not self.config.hardware_kali_wifi

        return None

    def _save_config_prompt(self) -> None:
        target = InputScreen(self.stdscr, "Save Configuration Profile", "Enter file path to save JSON config:", "config.json").run()
        if target:
            try:
                self.config.save_json(target)
                ConfirmScreen(self.stdscr, "Configuration Saved", f"Successfully saved configuration profile to:\n{os.path.abspath(target)}", is_alert=True).run()
            except Exception as e:
                ConfirmScreen(self.stdscr, "Save Error", f"Failed to save configuration: {e}", is_alert=True).run()

    def _load_config_prompt(self) -> None:
        target = InputScreen(self.stdscr, "Load Configuration Profile", "Enter file path of JSON config to load:", "config.json").run()
        if target:
            if not os.path.isfile(target):
                ConfirmScreen(self.stdscr, "File Not Found", f"No file found at: {target}", is_alert=True).run()
                return
            try:
                self.config = PostInstallConfig.load_json(target)
                ConfirmScreen(self.stdscr, "Configuration Loaded", f"Successfully loaded configuration profile from:\n{os.path.abspath(target)}", is_alert=True).run()
            except Exception as e:
                ConfirmScreen(self.stdscr, "Load Error", f"Failed to parse configuration: {e}", is_alert=True).run()


class OptionListScreen:
    """Single-selection radio screen with Vim navigation (j/k, g/G, l/Enter)."""

    def __init__(self, stdscr: curses.window, title: str, options: List[Tuple[str, str]], current_val: str):
        self.stdscr = stdscr
        self.title = title
        self.options = options
        self.current_val = current_val
        self.cursor_idx = 0
        for i, (k, _) in enumerate(options):
            if k == current_val:
                self.cursor_idx = i
                break

    def run(self) -> Optional[str]:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [g/G] Top/Bottom  [Enter/l/Space] Select  [Esc/h/q] Cancel ")

            box_h = min(max_y - 6, len(self.options) + 4)
            box_w = min(max_x - 4, 80)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))

            for i, (k, label) in enumerate(self.options):
                is_selected = (i == self.cursor_idx)
                is_active = (k == self.current_val)
                radio = "(*)" if is_active else "( )"
                line = f" {radio} {label}"

                attr = Colors.highlight(bold=True) if is_selected else Colors.normal()
                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 2, line.ljust(box_w - 4), attr)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            # Down: j / Down Arrow
            if key in (curses.KEY_DOWN, ord('j'), ord('J')):
                self.cursor_idx = (self.cursor_idx + 1) % len(self.options)

            # Up: k / Up Arrow
            elif key in (curses.KEY_UP, ord('k'), ord('K')):
                self.cursor_idx = (self.cursor_idx - 1) % len(self.options)

            # Top: g / Home
            elif key in (curses.KEY_HOME, ord('g')):
                self.cursor_idx = 0

            # Bottom: G / End
            elif key in (curses.KEY_END, ord('G')):
                self.cursor_idx = len(self.options) - 1

            # Half-page scroll
            elif key in (4, 6, curses.KEY_NPAGE):
                self.cursor_idx = min(len(self.options) - 1, self.cursor_idx + 3)
            elif key in (21, 2, curses.KEY_PPAGE):
                self.cursor_idx = max(0, self.cursor_idx - 3)

            # Select & Confirm: Enter, l, Space
            elif key in (10, 13, curses.KEY_ENTER, ord('l'), ord(' ')):
                return self.options[self.cursor_idx][0]

            # Cancel / Back: Esc, h, q
            elif key in (ord('q'), ord('Q'), ord('h'), 27):
                return None


class SelectListScreen:
    """Multi-selection checklist screen with Vim navigation and toggles."""

    def __init__(self, stdscr: curses.window, title: str, options: List[Tuple[str, str, bool]]):
        self.stdscr = stdscr
        self.title = title
        self.options = options
        self.selected: Dict[str, bool] = {k: state for k, _, state in options}
        self.cursor_idx = 0

    def run(self) -> Optional[List[str]]:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [Space/x] Toggle  [a] All  [c] Clear  [g/G] Top/Bottom  [Enter] Confirm  [Esc/h/q] Cancel ")

            box_h = min(max_y - 6, len(self.options) + 4)
            box_w = min(max_x - 4, 88)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))

            for i, (k, label, _) in enumerate(self.options):
                is_selected = (i == self.cursor_idx)
                is_checked = self.selected.get(k, False)
                check = "[✓]" if is_checked else "[ ]"
                line = f" {check} {label}"

                if is_selected:
                    attr = Colors.highlight(bold=True)
                else:
                    attr = Colors.success(bold=True) if is_checked else Colors.normal()

                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 2, line.ljust(box_w - 4), attr)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            # Down: j / Down Arrow
            if key in (curses.KEY_DOWN, ord('j'), ord('J')):
                self.cursor_idx = (self.cursor_idx + 1) % len(self.options)

            # Up: k / Up Arrow
            elif key in (curses.KEY_UP, ord('k'), ord('K')):
                self.cursor_idx = (self.cursor_idx - 1) % len(self.options)

            # Top: g / Home
            elif key in (curses.KEY_HOME, ord('g')):
                self.cursor_idx = 0

            # Bottom: G / End
            elif key in (curses.KEY_END, ord('G')):
                self.cursor_idx = len(self.options) - 1

            # Half-page scroll
            elif key in (4, 6, curses.KEY_NPAGE):
                self.cursor_idx = min(len(self.options) - 1, self.cursor_idx + 3)
            elif key in (21, 2, curses.KEY_PPAGE):
                self.cursor_idx = max(0, self.cursor_idx - 3)

            # Toggle checkmark: Space or x
            elif key in (ord(' '), ord('x'), ord('X')):
                cur_k = self.options[self.cursor_idx][0]
                self.selected[cur_k] = not self.selected.get(cur_k, False)

            # Select All: a
            elif key in (ord('a'), ord('A')):
                for k, _, _ in self.options:
                    self.selected[k] = True

            # Clear All: c
            elif key in (ord('c'), ord('C')):
                for k, _, _ in self.options:
                    self.selected[k] = False

            # Confirm / Save: Enter or o
            elif key in (10, 13, curses.KEY_ENTER):
                return [k for k, _, _ in self.options if self.selected.get(k, False)]

            # Cancel / Back: Esc, h, q
            elif key in (27, ord('q'), ord('Q'), ord('h')):
                return None


class InputScreen:
    """Text entry dialog box."""

    def __init__(self, stdscr: curses.window, title: str, prompt: str, default_val: str = ""):
        self.stdscr = stdscr
        self.title = title
        self.prompt = prompt
        self.buffer = list(default_val)
        self.cursor_pos = len(self.buffer)

    def run(self) -> Optional[str]:
        curses.curs_set(1)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [Enter] Submit  [Esc] Cancel ")

            box_h = 8
            box_w = min(max_x - 4, 70)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))
            safe_addstr(self.stdscr, box_y + 2, box_x + 3, self.prompt, Colors.normal())

            field_w = box_w - 6
            field_y = box_y + 4
            field_x = box_x + 3
            input_text = "".join(self.buffer)
            safe_addstr(self.stdscr, field_y, field_x, input_text.ljust(field_w), Colors.highlight())

            cur_screen_x = field_x + self.cursor_pos
            try:
                self.stdscr.move(field_y, min(cur_screen_x, field_x + field_w - 1))
            except curses.error:
                pass

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (10, 13, curses.KEY_ENTER):
                curses.curs_set(0)
                return "".join(self.buffer).strip()
            elif key == 27:
                curses.curs_set(0)
                return None
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if self.cursor_pos > 0:
                    self.buffer.pop(self.cursor_pos - 1)
                    self.cursor_pos -= 1
            elif key == curses.KEY_DC:
                if self.cursor_pos < len(self.buffer):
                    self.buffer.pop(self.cursor_pos)
            elif key == curses.KEY_LEFT:
                self.cursor_pos = max(0, self.cursor_pos - 1)
            elif key == curses.KEY_RIGHT:
                self.cursor_pos = min(len(self.buffer), self.cursor_pos + 1)
            elif key >= 32 and key <= 126:
                if len(self.buffer) < field_w - 2:
                    self.buffer.insert(self.cursor_pos, chr(key))
                    self.cursor_pos += 1


class ConfirmScreen:
    """Confirmation modal dialog with Proceed / Cancel buttons and Vim navigation."""

    def __init__(self, stdscr: curses.window, title: str, message: str, is_alert: bool = False):
        self.stdscr = stdscr
        self.title = title
        self.message = message
        self.is_alert = is_alert
        self.btn_idx = 0

    def run(self) -> bool:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        lines = self.message.split("\n")

        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [h/l or ←/→] Switch Button  [Enter/y] Confirm  [Esc/n/q] Cancel ")

            box_h = min(max_y - 4, len(lines) + 6)
            box_w = min(max_x - 4, 76)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            color = Colors.warning(bold=True) if not self.is_alert else Colors.primary(bold=True)
            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, color)

            for i, line in enumerate(lines):
                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 3, line, Colors.normal())

            btn_y = box_y + box_h - 2
            if self.is_alert:
                btn_str = "[  OK (Enter)  ]"
                safe_addstr(self.stdscr, btn_y, box_x + (box_w - len(btn_str)) // 2, btn_str, Colors.highlight(bold=True))
            else:
                btn1 = "[  Proceed (Enter)  ]"
                btn2 = "[  Cancel (Esc)  ]"
                spacing = (box_w - len(btn1) - len(btn2) - 6) // 2
                x1 = box_x + 4
                x2 = x1 + len(btn1) + spacing

                attr1 = Colors.highlight(bold=True) if self.btn_idx == 0 else Colors.normal()
                attr2 = Colors.highlight(bold=True) if self.btn_idx == 1 else Colors.normal()

                safe_addstr(self.stdscr, btn_y, x1, btn1, attr1)
                safe_addstr(self.stdscr, btn_y, x2, btn2, attr2)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (10, 13, curses.KEY_ENTER):
                return (self.btn_idx == 0)
            elif key in (27, ord('q'), ord('Q'), ord('n'), ord('N')):
                return False
            # Vim navigation for buttons: h (left), l (right), j/k/Tab (toggle)
            elif key in (curses.KEY_LEFT, ord('h'), ord('H')):
                if not self.is_alert:
                    self.btn_idx = 0
            elif key in (curses.KEY_RIGHT, ord('l'), ord('L')):
                if not self.is_alert:
                    self.btn_idx = 1
            elif key in (curses.KEY_DOWN, curses.KEY_UP, ord('j'), ord('k'), 9):  # Tab
                if not self.is_alert:
                    self.btn_idx = 1 - self.btn_idx
            elif key in (ord('y'), ord('Y')):
                return True


class ExecutionScreen:
    """Live step-by-step progress monitor with spinner and scrolling log view."""

    def __init__(self, stdscr: curses.window, plan: ExecutionPlan, dry_run: bool = False):
        self.stdscr = stdscr
        self.plan = plan
        self.dry_run = dry_run
        self.log_lines: List[str] = []
        self.spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.spinner_idx = 0
        self.current_step_idx = 0
        self.plan_completed = False
        self.has_errors = False
        self.log_scroll_offset = 0
        self.auto_scroll = True
        self.event_queue: queue.Queue[ExecutionEvent] = queue.Queue()

    def _worker(self) -> None:
        try:
            for event in run_plan(self.plan, dry_run=self.dry_run):
                self.event_queue.put(event)
        except Exception as e:
            err_step = self.plan.steps[min(self.current_step_idx, len(self.plan.steps) - 1)]
            self.event_queue.put(ExecutionEvent(event_type="output", step_index=self.current_step_idx, step=err_step, message=f"Runner Error: {e}"))
            self.event_queue.put(ExecutionEvent(event_type="plan_complete", step_index=len(self.plan.steps) - 1, step=err_step, message="Completed with errors."))

    def run(self) -> bool:
        curses.curs_set(0)
        self.stdscr.nodelay(True)

        worker_thread = threading.Thread(target=self._worker, daemon=True)
        worker_thread.start()

        while True:
            # Drain event queue
            while True:
                try:
                    event = self.event_queue.get_nowait()
                    self.current_step_idx = event.step_index
                    if event.event_type == "output":
                        self.log_lines.append(event.message)
                    elif event.event_type == "step_start":
                        self.log_lines.append(f"==> {event.step.title}")
                    elif event.event_type == "step_complete":
                        self.log_lines.append(f"✓ Completed: {event.step.title} ({event.step.duration:.1f}s)")
                    elif event.event_type == "step_fail":
                        self.has_errors = True
                        self.log_lines.append(f"✖ ERROR: {event.step.title}")
                    elif event.event_type == "plan_complete":
                        self.plan_completed = True
                except queue.Empty:
                    break

            if not worker_thread.is_alive() and self.event_queue.empty():
                self.plan_completed = True

            self.spinner_idx = (self.spinner_idx + 1) % len(self.spinner_frames)

            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()

            status_txt = "DRY-RUN EXECUTION" if self.dry_run else "EXECUTING POST-INSTALLATION STEPS"
            sub_title = f"Step {min(len(self.plan.steps), self.current_step_idx + 1)} of {len(self.plan.steps)}"
            draw_header(self.stdscr, status_txt, sub_title)

            if not self.plan_completed:
                draw_footer(self.stdscr, " [j/k or ↑/↓] Scroll Logs  [G] Auto-scroll  Please wait while installing... ")
            else:
                draw_footer(self.stdscr, " [j/k or ↑/↓] Scroll Logs  Installation Finished! Press [Enter] or [q] to exit ")

            content_top = 3
            content_bottom = max_y - 2
            available_h = content_bottom - content_top + 1

            steps_h = min(12, max(6, int(available_h * 0.38)))
            log_h = available_h - steps_h - 1

            # Draw Steps Box
            draw_box(self.stdscr, content_top, 1, steps_h, max_x - 2, f"Execution Plan [./{self.plan.config.distro}/]", Colors.primary(bold=True))

            visible_steps = steps_h - 2
            step_offset = max(0, self.current_step_idx - visible_steps + 1)

            for i in range(visible_steps):
                s_idx = step_offset + i
                if s_idx >= len(self.plan.steps):
                    break
                step = self.plan.steps[s_idx]
                row_y = content_top + 1 + i

                if step.status == StepStatus.COMPLETED:
                    icon = "[✓]"
                    attr = Colors.success(bold=True)
                elif step.status == StepStatus.RUNNING:
                    icon = f"[{self.spinner_frames[self.spinner_idx]}]"
                    attr = Colors.warning(bold=True)
                elif step.status == StepStatus.FAILED:
                    icon = "[✗]"
                    attr = Colors.error(bold=True)
                else:
                    icon = "[·]"
                    attr = Colors.dim()

                step_line = f" {icon} {s_idx + 1}. {step.title}"
                safe_addstr(self.stdscr, row_y, 3, step_line, attr)

            # Draw Logs Box
            log_y = content_top + steps_h
            draw_box(self.stdscr, log_y, 1, log_h, max_x - 2, "Live Command Output & Logs", Colors.primary(bold=True))

            visible_logs = log_h - 2
            total_logs = len(self.log_lines)

            if self.auto_scroll:
                start_log_idx = max(0, total_logs - visible_logs)
            else:
                start_log_idx = max(0, min(self.log_scroll_offset, max(0, total_logs - visible_logs)))

            rendered_logs = self.log_lines[start_log_idx:start_log_idx + visible_logs]
            for l_i, l_text in enumerate(rendered_logs):
                l_attr = Colors.normal()
                if l_text.startswith("✓"):
                    l_attr = Colors.success(bold=True)
                elif l_text.startswith("✖") or "ERROR" in l_text:
                    l_attr = Colors.error(bold=True)
                elif l_text.startswith("==>") or l_text.startswith("[EXEC]"):
                    l_attr = Colors.accent(bold=True)
                elif l_text.startswith("[DRY-RUN]"):
                    l_attr = Colors.warning()
                safe_addstr(self.stdscr, log_y + 1 + l_i, 3, l_text[:max_x - 6], l_attr)

            self.stdscr.refresh()

            # Handle interactive scrolling & exit
            key = self.stdscr.getch()
            if key != -1:
                if key in (curses.KEY_UP, ord('k'), ord('K')):
                    self.auto_scroll = False
                    self.log_scroll_offset = max(0, (start_log_idx if self.auto_scroll else self.log_scroll_offset) - 1)
                elif key in (curses.KEY_DOWN, ord('j'), ord('J')):
                    self.log_scroll_offset = min(max(0, total_logs - visible_logs), (start_log_idx if self.auto_scroll else self.log_scroll_offset) + 1)
                    if self.log_scroll_offset >= total_logs - visible_logs:
                        self.auto_scroll = True
                elif key in (4, 6, curses.KEY_NPAGE):  # Ctrl+d / PageDown
                    self.log_scroll_offset = min(max(0, total_logs - visible_logs), (start_log_idx if self.auto_scroll else self.log_scroll_offset) + 5)
                    if self.log_scroll_offset >= total_logs - visible_logs:
                        self.auto_scroll = True
                elif key in (21, 2, curses.KEY_PPAGE):  # Ctrl+u / PageUp
                    self.auto_scroll = False
                    self.log_scroll_offset = max(0, (start_log_idx if self.auto_scroll else self.log_scroll_offset) - 5)
                elif key in (curses.KEY_HOME, ord('g')):
                    self.auto_scroll = False
                    self.log_scroll_offset = 0
                elif key in (curses.KEY_END, ord('G')):
                    self.auto_scroll = True
                elif self.plan_completed and key in (10, 13, curses.KEY_ENTER, ord('q'), ord('Q'), 27):
                    self.stdscr.nodelay(False)
                    return not self.has_errors

            time.sleep(0.033)  # Smooth 30 FPS rendering loop
