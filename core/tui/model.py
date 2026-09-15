#!/usr/bin/env python3
"""
UI-agnostic menu model shared by the Textual and curses front-ends.

Holds the global menu contents (items, previews) and what selecting an item
does. Front-ends supply a `Prompter` that renders the actual dialogs, so the
menu options only need to be defined once.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Protocol, Tuple

from core.config import PostInstallConfig
from core.detector import SystemInfo
from core.runner import ExecutionPlan, discover_extra_scripts


@dataclass
class MenuItem:
    key: str
    label: str
    value_display: str
    description: str
    preview_lines: List[str] = field(default_factory=list)
    action_type: str = "custom"
    is_action: bool = False


@dataclass
class MenuState:
    config: PostInstallConfig
    sysinfo: SystemInfo
    base_dir: Path


class Prompter(Protocol):
    """Dialogs a front-end must provide. Cancelling returns None / False."""

    async def select_one(self, title: str, options: List[Tuple[str, str]], current: Optional[str]) -> Optional[str]: ...

    async def select_many(self, title: str, options: List[Tuple[str, str, bool]]) -> Optional[List[str]]: ...

    async def ask_text(self, title: str, prompt: str, default: str = "") -> Optional[str]: ...

    async def confirm(self, title: str, message: str) -> bool: ...

    async def notify(self, title: str, message: str) -> None: ...


MODULAR_DISTROS = ("arch", "debian", "fedora")

CODING_SOURCES = {
    "arch": [" • visual-studio-code-bin", " • cursor-bin", " • claude-code", " • android-studio", " • flutter-bin", " • antigravity-cli & antigravity-ide"],
    "debian": [" • neovim (built from source)", " • VS Code (Pacstall vscode-deb / Microsoft repo)", " • Cursor (.deb)",
               " • Claude Code (native installer)", " • Android Studio (Pacstall / Flathub)", " • Flutter (official tarball)", " • Antigravity (Google apt repo)"],
    "fedora": [" • neovim (dnf)", " • VS Code (Microsoft repo)", " • Cursor (.rpm)",
               " • Claude Code (@anthropic-ai/claude-code npm)", " • Android Studio (Flathub)", " • Flutter (official tarball)", " • Antigravity (Google rpm repo)"],
}

EXIT_TITLE = "Exit Installer?"
EXIT_MESSAGE = "Are you sure you want to exit without applying changes?"

FINISH_MESSAGE = (
    "Post-installation configuration has finished successfully!\n\n"
    "Please restart your session or reboot your system\n"
    "for all user permissions, group memberships, and\n"
    "system services to take full effect."
)


def build_menu_items(state: MenuState) -> List[MenuItem]:
    cfg = state.config
    info = state.sysinfo
    distro = cfg.distro
    items: List[MenuItem] = []

    # 1. Distribution
    items.append(MenuItem(
        key="distro",
        label="  Distribution / Target OS",
        value_display=f"[{distro.upper()}] {cfg.distro_name}",
        description="Active distribution workspace folder.",
        preview_lines=[
            f"Active OS Folder: ./{distro}/",
            f"Target OS:        {cfg.distro_name}",
            f"Detected System:  {info.distro_name} ({info.distro_id})",
            f"Host CPU:         {info.cpu_model or info.cpu_vendor.upper()}",
            f"Host GPU:         {', '.join(info.gpu_descriptions) if info.gpu_descriptions else 'Generic'}",
            "",
            f"The installer executes ONLY modular scripts from {distro}/:",
            *([
                f" • {distro}/{distro}.sh",
                f" • {distro}/desktop/kde.sh & {distro}/desktop/tiling.sh",
                f" • {distro}/hardware/asus.sh, touchpad.sh & gpu/",
                f" • {distro}/virt/kvm-qemu.sh & {distro}/virt/vmware-workstation.sh",
                f" • {distro}/apps/ (docker, coding, gaming, ...)",
            ] if distro in MODULAR_DISTROS else [f" • {distro}/{distro}.sh", f" • {distro}/apps/"])
        ],
        action_type="radio"
    ))

    # ==========================================================
    # ARCH / DEBIAN / FEDORA MODULAR MENU ITEMS (STRICTLY <distro>/ CONTENT)
    # ==========================================================
    if distro in MODULAR_DISTROS:
        d = distro
        is_arch = distro == "arch"
        # 2. Desktop Environment (arch/desktop/kde.sh or arch/desktop/tiling.sh)
        de_map = {"kde": f"KDE Plasma ({d}/desktop/kde.sh)", "tiling": f"X11 Tiling ({d}/desktop/tiling.sh)", "none": "None (Skip Desktop)"}
        de_label = de_map.get(cfg.desktop_environment, "None")
        items.append(MenuItem(
            key="desktop_environment",
            label="  Desktop Environment",
            value_display=f"[{cfg.desktop_environment.upper()}]",
            description=f"KDE Plasma or X11 Tiling setup from {d}/desktop/.",
            preview_lines=[
                f"Current selection: {de_label}",
                "",
                f"Modular scripts in {d}/desktop/:",
                f" • KDE Plasma ({d}/desktop/kde.sh):",
                "   Plasma desktop, Wayland/X11 sessions, Dolphin, Kate, Konsole, Ark, KDE Connect, portal services",
                "",
                f" • X11 Tiling ({d}/desktop/tiling.sh):",
                "   Polybar, Picom compositor, Rofi, Dunst, Feh, Zathura, i3lock-color, Dracula GTK,",
                f"   and Precision Touchpad configuration ({d}/hardware/touchpad.sh)",
                "",
                " • None:",
                "   Skip desktop environment setup"
            ],
            action_type="radio"
        ))

        # 3. Hardware Drivers (<distro>/hardware/asus.sh & <distro>/hardware/gpu/)
        hw_tags = []
        if cfg.hardware_asus:
            hw_tags.append(f"ASUS ROG ({cfg.hardware_asus_battery_limit}%)")
        if cfg.hardware_amd_gpu:
            hw_tags.append("AMD + Pro" if is_arch and cfg.hardware_amd_pro else "AMD")
        if cfg.hardware_intel_gpu:
            hw_tags.append("Intel")
        if cfg.hardware_nvidia_gpu:
            hw_tags.append("NVIDIA")
        hw_display = ", ".join(hw_tags) if hw_tags else "[None]"

        items.append(MenuItem(
            key="hardware",
            label=f"  Hardware & Drivers ({d}/hardware/)",
            value_display=f"[{hw_display}]",
            description="ASUS ROG tools and AMD / Intel / NVIDIA drivers.",
            preview_lines=[
                f"Detected Chassis: {info.chassis_model or 'Generic'} (ASUS: {info.is_asus})",
                f"Detected CPU:     {info.cpu_model or info.cpu_vendor}",
                f"Detected GPU:     {', '.join(info.gpu_descriptions) if info.gpu_descriptions else 'Generic'}",
                "",
                f"Modular scripts in {d}/hardware/:",
                f" • ASUS ROG (asus.sh): {'[Yes] asusctl, fan curves, ' + str(cfg.hardware_asus_battery_limit) + '% limit' if cfg.hardware_asus else '[No]'}",
                f" • AMD (gpu/amd.sh): {'[Yes] amd-ucode, Mesa, Vulkan-Radeon, amd_pstate GRUB' + (' + AMD Pro (AUR)' if is_arch and cfg.hardware_amd_pro else '') if cfg.hardware_amd_gpu else '[No]'}",
                f" • Intel (gpu/intel.sh): {'[Yes] intel-ucode, Mesa, Vulkan-Intel, VA-API' if cfg.hardware_intel_gpu else '[No]'}",
                f" • NVIDIA (gpu/nvidia.sh): {'[Yes] nvidia-open-dkms, power config, suspend services' if cfg.hardware_nvidia_gpu else '[No]'}"
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
            label=f"  Virtualization ({d}/virt/)",
            value_display=f"[{virt_display}]",
            description="KVM/QEMU virt-manager and VMware Workstation.",
            preview_lines=[
                f"Modular scripts in {d}/virt/:",
                f" • KVM/QEMU ({d}/virt/kvm-qemu.sh): {'[Yes] virt-manager, libvirtd bridge network' if cfg.virt_kvm_qemu else '[No]'}",
                f" • VMware Workstation ({d}/virt/vmware-workstation.sh): {('[Yes] AUR build & kernel modules' if is_arch else '[Yes] runs a downloaded VMware bundle') if cfg.virt_vmware_workstation else '[No]'}"
            ],
            action_type="multiselect"
        ))

        # 5. Docker (arch/apps/docker.sh)
        items.append(MenuItem(
            key="docker_enabled",
            label=f"  Docker CE ({d}/apps/docker.sh)",
            value_display="[Yes]" if cfg.docker_enabled else "[No]",
            description="Docker Engine, Compose plugin, Buildx, and user group permissions.",
            preview_lines=[
                f"Script: {d}/apps/docker.sh",
                f"Status: {'Yes' if cfg.docker_enabled else 'No'}",
                "",
                "Configures:",
                " • docker, docker-compose, docker-buildx" if is_arch else " • docker-ce, compose & buildx plugins (official Docker repo)",
                f" • sudo usermod -aG docker {info.username}",
                " • sudo systemctl enable --now docker.service"
            ],
            action_type="toggle"
        ))

        # 6. Coding Tools (from arch/arch.sh aur_coding_packages)
        code_display = f"[{len(cfg.coding_tools)} tools]" if cfg.coding_enabled else "[No]"
        items.append(MenuItem(
            key="coding",
            label="  Developer Tools (AUR)",
            value_display=code_display,
            description="VS Code, Cursor, Claude Code, Android Studio, Flutter, and Antigravity.",
            preview_lines=[
                "Packages from arch/arch.sh (aur_coding_packages):" if is_arch else f"Script: {d}/apps/coding.sh",
                f" • Active: {', '.join(cfg.coding_tools) if cfg.coding_tools else 'None'}",
                "",
                "Available Packages:",
                *CODING_SOURCES[distro]
            ],
            action_type="multiselect"
        ))

        if is_arch:
            # 7. Burp Suite Pro (arch/apps/burp/install.sh)
            items.append(MenuItem(
                key="security_burp",
                label="  Burp Suite Pro (arch/apps/burp/)",
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
            label="  Gaming Stack & Wine",
            value_display="[Yes]" if cfg.gaming_enabled else "[No]",
            description="Wine-staging, Lutris, GameMode, Proton DXVK, and 32-bit graphics runtimes.",
            preview_lines=[
                f"Packages from {d}/apps/gaming.sh:",
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
            label="󰢩  AI / ML Acceleration (ROCm)",
            value_display="[Yes]" if cfg.ai_ml_enabled else "[No]",
            description="AMD ROCm SDK, PyTorch ROCm, and ONNX Runtime ROCm.",
            preview_lines=[
                "Packages from arch/arch.sh (ai_ml_packages):" if is_arch else f"Script: {d}/apps/aiml.sh",
                f"Status: {'Yes' if cfg.ai_ml_enabled else 'No'}",
                "",
                "Includes:",
                " • rocm-hip-sdk, rocm-opencl-sdk, rocm-ml-libraries",
                " • python-pytorch-rocm, python-onnxruntime-rocm" if is_arch else " • PyTorch ROCm (pip, ~/.venvs/rocm)"
            ],
            action_type="toggle"
        ))


        # Debian / Fedora package sources and productivity apps
        if distro == "debian":
            items.append(MenuItem(
                key="repos_pacstall",
                label="  Pacstall (AUR for Debian)",
                value_display="[Yes]" if cfg.repos_pacstall else "[No]",
                description="Pacstall provides apps not packaged in Debian (VS Code, Android Studio, Thorium, Zen...).",
                preview_lines=[
                    "Script: debian/system/pacstall.sh",
                    f"Status: {'Yes' if cfg.repos_pacstall else 'No'}",
                    "",
                    "Installs with:",
                    ' • sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)"',
                    " • Packages: pacstall -I <name> -P"
                ],
                action_type="toggle"
            ))
        if not is_arch:
            items.append(MenuItem(
                key="repos_flatpak",
                label="  Flatpak & Flathub",
                value_display="[Yes]" if cfg.repos_flatpak else "[No]",
                description="Flathub is used for apps without a native package.",
                preview_lines=[
                    f"Script: {d}/system/flatpak.sh",
                    f"Status: {'Yes' if cfg.repos_flatpak else 'No'}"
                ],
                action_type="toggle"
            ))
            items.append(MenuItem(
                key="productivity_enabled",
                label="  Productivity Apps",
                value_display="[Yes]" if cfg.productivity_enabled else "[No]",
                description="Equivalents of the Arch AUR app list.",
                preview_lines=[
                    f"Script: {d}/apps/productivity.sh",
                    f"Status: {'Yes' if cfg.productivity_enabled else 'No'}",
                    "",
                    "Includes:",
                    " • AnyDesk, LocalSend, Thorium, Zen Browser, Vesktop, Obsidian",
                    " • ani-cli, gallery-dl, markitdown"
                ],
                action_type="toggle"
            ))

        if is_arch:
            # 10. AUR Helper Selection (arch/apps/paru.sh & arch/apps/yay.sh)
            aur_map = {
                "paru": "Paru (Rust, Recommended)",
                "yay": "Yay (Go)",
                "both": "Both (Paru + Yay)",
                "none": "None / Skip"
            }
            items.append(MenuItem(
                key="aur_helper",
                label="  AUR Helper Selection",
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
                label="  Mirror Optimization (Reflector India)",
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
            label="  Burp Suite Pro (kali/apps/burp/)",
            value_display="[Yes]" if cfg.security_burp else "[No]",
            description="Burp Suite Professional installer from kali/apps/burp/install.sh.",
            preview_lines=["Script: kali/apps/burp/install.sh", f"Status: {'Yes' if cfg.security_burp else 'No'}"],
            action_type="toggle"
        ))
        items.append(MenuItem(
            key="kali_metapackages",
            label="  Kali Metapackages",
            value_display=f"[{', '.join(cfg.security_kali_metapackages) if cfg.security_kali_metapackages else 'None'}]",
            description="kali-linux-everything, kali-linux-large, kali-linux-labs.",
            preview_lines=[f"Active suites: {', '.join(cfg.security_kali_metapackages)}"],
            action_type="multiselect"
        ))
        items.append(MenuItem(
            key="hardware_kali_wifi",
            label="  WiFi Driver (kali/hardware/wifi.sh)",
            value_display="[Yes]" if cfg.hardware_kali_wifi else "[No]",
            description="Realtek 8821AU USB WiFi DKMS driver.",
            preview_lines=["Script: kali/hardware/wifi.sh"],
            action_type="toggle"
        ))
        items.append(MenuItem(
            key="docker_enabled",
            label="  Docker CE (kali/apps/docker.sh)",
            value_display="[Yes]" if cfg.docker_enabled else "[No]",
            description="Docker CE engine configured for Kali.",
            preview_lines=["Script: kali/apps/docker.sh"],
            action_type="toggle"
        ))

    # ==========================================================
    # TERMUX MENU ITEMS (STRICTLY termux/ CONTENT)
    # ==========================================================
    elif distro == "termux":
        items.append(MenuItem(
            key="termux_core",
            label="  Termux Setup (termux/termux.sh)",
            value_display="[Yes]",
            description="Termux storage, zsh, tmux, python, and dotfiles.",
            preview_lines=["Script: termux/termux.sh"],
            action_type="toggle"
        ))
        items.append(MenuItem(
            key="termux_font",
            label="  Nerd Font (termux/system/font.sh)",
            value_display="[Yes]" if cfg.theme_nerd_fonts else "[No]",
            description="JetBrains Mono Nerd Font for Termux.",
            preview_lines=["Script: termux/system/font.sh"],
            action_type="toggle"
        ))

    # ==========================================================
    # AUTO-DISCOVERED EXTRA APP SCRIPTS (ANY DISTRO: <distro>/apps/)
    # ==========================================================
    discovered = discover_extra_scripts(state.base_dir, distro)
    if discovered:
        enabled_count = sum(1 for s in discovered if s in cfg.extra_scripts)
        items.append(MenuItem(
            key="extra_scripts",
            label=f"  Extra App Scripts ({distro}/apps/)",
            value_display=f"[{enabled_count}/{len(discovered)}]",
            description=f"Auto-discovered install scripts from {distro}/apps/. Toggle individually.",
            preview_lines=[
                f"Discovered scripts (drop a .sh file in {distro}/apps/ to add more):",
                "",
                *[f" • {s}.sh {'[Enabled]' if s in cfg.extra_scripts else '[Disabled]'}" for s in discovered]
            ],
            action_type="multiselect"
        ))

    # ==========================================================
    # ACTION BUTTONS AT BOTTOM
    # ==========================================================
    items.append(MenuItem(
        key="action_install",
        label="  Install",
        value_display="[Start post-installation]",
        description=f"Execute the post-installation plan using ./{distro}/ modular scripts.",
        preview_lines=[
            "========================================",
            f"   READY TO RUN ./{distro.upper()}/ POST-INSTALL",
            "========================================",
            f"Target OS: {cfg.distro_name}",
            "",
            "Press ENTER to review planned steps",
            "and execute the automated installer."
        ],
        action_type="action",
        is_action=True
    ))

    items.append(MenuItem(
        key="action_save",
        label="  Save Configuration",
        value_display="[Save to JSON]",
        description="Export all configured options to a JSON profile.",
        preview_lines=["Save your current settings to a JSON profile."],
        action_type="action",
        is_action=True
    ))

    items.append(MenuItem(
        key="action_load",
        label="  Load Configuration",
        value_display="[Load from JSON]",
        description="Import a previously saved JSON configuration file.",
        preview_lines=["Import settings from a local JSON file."],
        action_type="action",
        is_action=True
    ))

    items.append(MenuItem(
        key="action_abort",
        label="  Abort",
        value_display="[Exit installer]",
        description="Exit without applying changes.",
        preview_lines=["Exit the post-installation suite."],
        action_type="action",
        is_action=True
    ))

    return items


# Boolean items that can be flipped in place (Space / x) without a dialog.
_TOGGLES = {
    "docker_enabled": "docker_enabled",
    "security_burp": "security_burp",
    "gaming_enabled": "gaming_enabled",
    "ai_ml_enabled": "ai_ml_enabled",
    "hardware_kali_wifi": "hardware_kali_wifi",
    "repos_mirror_ranking": "repos_mirror_ranking",
    "repos_pacstall": "repos_pacstall",
    "repos_flatpak": "repos_flatpak",
    "productivity_enabled": "productivity_enabled",
}


def quick_toggle(state: MenuState, key: str) -> bool:
    """Flip a boolean item in place. Returns True if the item was toggleable."""
    attr = _TOGGLES.get(key)
    if attr is None:
        return False
    setattr(state.config, attr, not getattr(state.config, attr))
    return True


async def handle_item_select(state: MenuState, item: MenuItem, ui: Prompter) -> Optional[str]:
    """Run the action for a menu item. Returns "install", "exit", or None."""
    cfg = state.config
    k = item.key

    if k == "action_install":
        return "install"
    elif k == "action_save":
        await save_config(state, ui)
    elif k == "action_load":
        await load_config(state, ui)
    elif k == "action_abort":
        if await ui.confirm(EXIT_TITLE, EXIT_MESSAGE):
            return "exit"

    elif quick_toggle(state, k):
        pass

    elif k == "distro":
        options = [
            ("arch", "Arch Linux (arch/ modular folder)"),
            ("debian", "Debian / Ubuntu (debian/ modular folder)"),
            ("fedora", "Fedora (fedora/ modular folder)"),
            ("kali", "Kali Linux (kali/ modular folder)"),
            ("termux", "Termux (termux/ modular folder)")
        ]
        sel = await ui.select_one("Select Active Distribution Folder", options, cfg.distro)
        if sel:
            cfg.set_distro(sel)

    elif k == "desktop_environment":
        options = [
            ("kde", f"KDE Plasma ({cfg.distro}/desktop/kde.sh)"),
            ("tiling", f"X11 Tiling Window Manager ({cfg.distro}/desktop/tiling.sh)"),
            ("none", "None / Headless (Skip desktop environment setup)")
        ]
        sel = await ui.select_one(f"Select Desktop Environment ({cfg.distro}/desktop/)", options, cfg.desktop_environment)
        if sel:
            cfg.desktop_environment = sel

    elif k == "hardware":
        options = [
            ("asus", f"ASUS ROG Tools & Fan Curves ({cfg.distro}/hardware/asus.sh)", cfg.hardware_asus),
            ("amd", f"AMD CPU/GPU Drivers & Kernel Optimization ({cfg.distro}/hardware/gpu/amd.sh)", cfg.hardware_amd_gpu),
            ("intel", f"Intel CPU/GPU Drivers ({cfg.distro}/hardware/gpu/intel.sh)", cfg.hardware_intel_gpu),
            ("nvidia", f"NVIDIA GPU Drivers ({cfg.distro}/hardware/gpu/nvidia.sh)", cfg.hardware_nvidia_gpu)
        ]
        res = await ui.select_many(f"Hardware & Drivers ({cfg.distro}/hardware/)", options)
        if res is not None:
            cfg.hardware_asus = "asus" in res
            cfg.hardware_amd_gpu = "amd" in res
            cfg.hardware_intel_gpu = "intel" in res
            cfg.hardware_nvidia_gpu = "nvidia" in res

            if cfg.hardware_amd_gpu and cfg.distro == "arch":
                pro_options = [
                    ("no", "No  - Open-source Mesa stack only (Recommended)"),
                    ("yes", "Yes - Also install AMD Pro AUR packages (AMF, OpenCL, OGLP)")
                ]
                current = "yes" if cfg.hardware_amd_pro else "no"
                sel = await ui.select_one("Install AMD Pro Packages? (arch/hardware/gpu/amd.sh --pro)", pro_options, current)
                if sel:
                    cfg.hardware_amd_pro = sel == "yes"
            else:
                cfg.hardware_amd_pro = False

            if cfg.hardware_asus:
                limit_str = await ui.ask_text("ASUS Battery Limit", "Enter battery charge threshold percentage (50-100):", str(cfg.hardware_asus_battery_limit))
                if limit_str and limit_str.isdigit():
                    cfg.hardware_asus_battery_limit = max(50, min(100, int(limit_str)))

    elif k == "virtualization":
        options = [
            ("kvm", f"KVM / QEMU & virt-manager ({cfg.distro}/virt/kvm-qemu.sh)", cfg.virt_kvm_qemu),
            ("vmware_host", f"VMware Workstation Host ({cfg.distro}/virt/vmware-workstation.sh)", cfg.virt_vmware_workstation)
        ]
        res = await ui.select_many(f"Virtualization Setup ({cfg.distro}/virt/)", options)
        if res is not None:
            cfg.virt_kvm_qemu = "kvm" in res
            cfg.virt_vmware_workstation = "vmware_host" in res

    elif k == "coding":
        options = [] if cfg.distro == "arch" else [("neovim", "Neovim", "neovim" in cfg.coding_tools)]
        options += [
            ("vscode", "Visual Studio Code (visual-studio-code-bin)", "vscode" in cfg.coding_tools),
            ("cursor", "Cursor AI Code Editor (cursor-bin)", "cursor" in cfg.coding_tools),
            ("claude_code", "Claude Code (claude-code)", "claude_code" in cfg.coding_tools),
            ("android_studio", "Android Studio (android-studio)", "android_studio" in cfg.coding_tools),
            ("flutter", "Flutter SDK (flutter-bin)", "flutter" in cfg.coding_tools),
            ("antigravity", "Antigravity CLI & IDE", "antigravity" in cfg.coding_tools)
        ]
        title = "Developer & Coding Stack (arch/arch.sh aur_coding_packages)" if cfg.distro == "arch" else f"Developer & Coding Stack ({cfg.distro}/apps/coding.sh)"
        res = await ui.select_many(title, options)
        if res is not None:
            cfg.coding_tools = res
            cfg.coding_enabled = len(res) > 0

    elif k == "extra_scripts":
        discovered = discover_extra_scripts(state.base_dir, cfg.distro)
        options = [(s, f"{s}.sh", s in cfg.extra_scripts) for s in discovered]
        res = await ui.select_many(f"Extra App Scripts ({cfg.distro}/apps/)", options)
        if res is not None:
            cfg.extra_scripts = res

    elif k == "aur_helper":
        options = [
            ("paru", "Paru (Rust, fast, feature-rich - Recommended)"),
            ("yay", "Yay (Go, classic Arch AUR helper)"),
            ("both", "Both (Install both Paru and Yay)"),
            ("none", "None / Skip AUR Helper")
        ]
        sel = await ui.select_one("Select AUR Helper (arch/apps/)", options, cfg.aur_helper)
        if sel:
            cfg.aur_helper = sel

    elif k == "kali_metapackages":
        options = [
            ("everything", "kali-linux-everything (All Kali tools, ~10GB+)", "everything" in cfg.security_kali_metapackages),
            ("large", "kali-linux-large (Extended default toolset)", "large" in cfg.security_kali_metapackages),
            ("labs", "kali-linux-labs (Vulnerable testing environments)", "labs" in cfg.security_kali_metapackages)
        ]
        res = await ui.select_many("Kali Linux Metapackages", options)
        if res is not None:
            cfg.security_kali_metapackages = res

    return None


async def save_config(state: MenuState, ui: Prompter) -> None:
    target = await ui.ask_text("Save Configuration Profile", "Enter file path to save JSON config:", "config.json")
    if target:
        try:
            state.config.save_json(target)
            await ui.notify("Configuration Saved", f"Successfully saved configuration profile to:\n{os.path.abspath(target)}")
        except Exception as e:
            await ui.notify("Save Error", f"Failed to save configuration: {e}")


async def load_config(state: MenuState, ui: Prompter) -> None:
    target = await ui.ask_text("Load Configuration Profile", "Enter file path of JSON config to load:", "config.json")
    if target:
        if not os.path.isfile(target):
            await ui.notify("File Not Found", f"No file found at: {target}")
            return
        try:
            state.config = PostInstallConfig.load_json(target)
            await ui.notify("Configuration Loaded", f"Successfully loaded configuration profile from:\n{os.path.abspath(target)}")
        except Exception as e:
            await ui.notify("Load Error", f"Failed to parse configuration: {e}")


def install_summary(config: PostInstallConfig, plan: ExecutionPlan) -> str:
    lines = [
        f"Target Distribution:  {config.distro_name} ({config.distro})",
        f"Desktop Environment:  {config.desktop_environment.upper()}",
        f"Total Planned Steps:  {len(plan.steps)}",
        "",
        "Active Modules to Execute:"
    ]
    for s in plan.steps[:6]:
        lines.append(f" • {s.title}")
    if len(plan.steps) > 6:
        lines.append(f" • ... and {len(plan.steps) - 6} additional steps")
    lines.extend(["", "Would you like to start the post-installation process?"])
    return "\n".join(lines)


_PROGRESS_RE = re.compile(
    r"^\s*\d+[\s.%].*(?:Total|Received|Xferd|Speed|ETA|[kMGT]i?B[/\s])"  # curl/wget progress
    r"|^\s*%\s*Total\b|^\s*Dload\s+Upload\b"                             # curl progress table header
    r"|^\s*\d+\s+[\d.]+[kMGT]?\s+\d+"                                    # curl compact progress
    r"|^\(?\d+/\d+\)\s*(?:downloading|installing|upgrading|loading)"       # pacman/paru progress bars
    r"|^\s*(?:Downloading|Fetching|Collecting)\s.+\s\d+%"                  # pip/npm progress
    r"|^\s*\d+%\s*\|"                                                      # pip-style bar
    r"|^\s*(?:Reading package lists|Building dependency tree|Reading state information)\b"  # apt cache scanning
    r"|^\s*Progress:\s*\[\s*\d+%"                                         # dpkg progress bar
    r"|^\s*\(\s*Reading database\s*\.\.\."                                 # dpkg database scan
    r"|(?:\.\.\.|\b)\s*\d+%\s*$"                                          # any line ending in percent progress
    r"|\[\s*\d+%\s*\]"                                                    # [ 50%] style progress
, re.IGNORECASE)


def is_progress_line(text: str) -> bool:
    """Detect repetitive download/build/package progress lines (apt, curl, wget, pacman, pip)."""
    return bool(_PROGRESS_RE.search(text))

