#!/usr/bin/env python3
"""
Configuration state model for the post-installation suite.
Handles user selections, serialization, saving/loading JSON profiles, and system defaults.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from core.detector import SystemInfo, detect_system


@dataclass
class PostInstallConfig:
    # Target Platform
    distro: str = "arch"  # arch, debian, fedora, kali, termux
    distro_name: str = "Arch Linux"

    # Desktop Environment / Window Manager
    desktop_environment: str = "kde"  # kde, tiling, none

    # Hardware & Power Drivers
    hardware_asus: bool = False
    hardware_asus_battery_limit: int = 85
    hardware_touchpad: bool = False
    hardware_amd_gpu: bool = False
    hardware_kali_wifi: bool = False

    # Virtualization
    virt_kvm_qemu: bool = False
    virt_vmware_workstation: bool = False
    virt_open_vm_tools: bool = False

    # Containerization
    docker_enabled: bool = True

    # Coding & Development Tools
    coding_enabled: bool = True
    coding_tools: list[str] = field(
        default_factory=lambda: [
            "neovim",
            "vscode",
            "cursor",
            "android_studio",
            "flutter",
            "antigravity",
        ]
    )

    # Security & Pentest
    security_burp: bool = False
    security_kali_metapackages: list[str] = field(
        default_factory=list
    )  # everything, large, labs
    security_searchsploit_update: bool = False
    security_kali_new_user: str = ""
    security_kali_remove_default: bool = False
    security_kali_autologin: bool = False

    # Gaming & Wine Runtimes
    gaming_enabled: bool = False

    # AI / Machine Learning (ROCm / PyTorch / ONNX)
    ai_ml_enabled: bool = False

    # Themes, Fonts & Shell
    shell_zsh: bool = True
    shell_starship: bool = True
    theme_nerd_fonts: bool = True
    theme_gtk_icons: bool = True

    # Mirrors & Repositories
    repos_mirror_ranking: bool = True  # Reflector on Arch, DNF speed on Fedora
    aur_helper: str = "paru"  # paru, yay, both, none (Arch)
    repos_aur_paru: bool = True  # Arch legacy compat
    repos_pacstall: bool = False  # Debian
    repos_rpmfusion_copr: bool = True  # Fedora

    # Dotfiles & Config
    dotfiles_clone_link: bool = True
    neovim_config_clone: bool = True
    create_screenshot_dir: bool = True

    # Advanced / Custom
    custom_commands: list[str] = field(default_factory=list)

    def set_distro(self, distro_id: str) -> None:
        self.distro = distro_id
        names = {
            "arch": "Arch Linux",
            "debian": "Debian / Ubuntu",
            "fedora": "Fedora",
            "kali": "Kali Linux",
            "termux": "Termux",
        }
        self.distro_name = names.get(distro_id, distro_id.capitalize())

    @classmethod
    def default_for_system(cls, info: SystemInfo | None = None) -> PostInstallConfig:
        if info is None:
            info = detect_system()

        cfg = cls()
        cfg.distro = info.distro_id if info.distro_id != "unknown" else "arch"
        cfg.distro_name = info.distro_name

        # Distro specific presets
        if cfg.distro == "arch":
            cfg.desktop_environment = "kde"
            cfg.hardware_asus = info.is_asus
            cfg.hardware_touchpad = False  # only enabled when X11 tiling is chosen
            cfg.hardware_amd_gpu = "amd" in info.gpu_vendors
            cfg.virt_kvm_qemu = True
            cfg.virt_vmware_workstation = False
            cfg.virt_open_vm_tools = info.virt_type == "vmware"
            cfg.docker_enabled = True
            cfg.coding_enabled = True
            cfg.security_burp = False
            cfg.gaming_enabled = True
            cfg.ai_ml_enabled = (
                "amd" in info.gpu_vendors and not info.virt_type.startswith("vm")
            )
            cfg.repos_mirror_ranking = True
            cfg.repos_aur_paru = True
            cfg.theme_nerd_fonts = True
            cfg.theme_gtk_icons = True
            cfg.shell_zsh = True
            cfg.shell_starship = True

        elif cfg.distro == "kali":
            cfg.desktop_environment = "none"  # Kali comes with XFCE/GNOME pre-installed
            cfg.hardware_asus = False
            cfg.hardware_touchpad = False
            cfg.hardware_amd_gpu = False
            cfg.hardware_kali_wifi = True
            cfg.virt_kvm_qemu = False
            cfg.virt_vmware_workstation = False
            cfg.virt_open_vm_tools = info.virt_type == "vmware"
            cfg.docker_enabled = True
            cfg.coding_enabled = False
            cfg.security_burp = True
            cfg.security_kali_metapackages = ["large"]
            cfg.security_searchsploit_update = True
            cfg.gaming_enabled = False
            cfg.ai_ml_enabled = False
            cfg.repos_mirror_ranking = False
            cfg.theme_nerd_fonts = True
            cfg.shell_zsh = True
            cfg.shell_starship = True
            cfg.dotfiles_clone_link = True

        elif cfg.distro == "debian":
            cfg.desktop_environment = "none"
            cfg.hardware_asus = False
            cfg.hardware_touchpad = False
            cfg.hardware_amd_gpu = False
            cfg.virt_open_vm_tools = info.virt_type == "vmware"
            cfg.docker_enabled = True
            cfg.coding_enabled = True
            cfg.repos_pacstall = True
            cfg.theme_nerd_fonts = True
            cfg.shell_zsh = True
            cfg.shell_starship = True

        elif cfg.distro == "fedora":
            cfg.desktop_environment = "none"
            cfg.hardware_asus = False
            cfg.hardware_touchpad = False
            cfg.hardware_amd_gpu = False
            cfg.virt_open_vm_tools = info.virt_type == "vmware"
            cfg.docker_enabled = True
            cfg.coding_enabled = True
            cfg.gaming_enabled = True
            cfg.repos_rpmfusion_copr = True
            cfg.repos_mirror_ranking = True
            cfg.theme_nerd_fonts = True
            cfg.shell_zsh = True
            cfg.shell_starship = True

        elif cfg.distro == "termux":
            cfg.desktop_environment = "none"
            cfg.hardware_asus = False
            cfg.hardware_touchpad = False
            cfg.hardware_amd_gpu = False
            cfg.virt_kvm_qemu = False
            cfg.virt_vmware_workstation = False
            cfg.virt_open_vm_tools = False
            cfg.docker_enabled = False
            cfg.coding_enabled = True
            cfg.coding_tools = ["neovim"]
            cfg.gaming_enabled = False
            cfg.ai_ml_enabled = False
            cfg.repos_mirror_ranking = False
            cfg.repos_aur_paru = False
            cfg.theme_nerd_fonts = True
            cfg.theme_gtk_icons = False
            cfg.shell_zsh = True
            cfg.shell_starship = True
            cfg.dotfiles_clone_link = True

        return cfg

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> PostInstallConfig:
        cfg = cls()
        for k, v in data.items():
            if hasattr(cfg, k):
                setattr(cfg, k, v)
        return cfg

    def save_json(self, file_path: str | Path) -> None:
        path = Path(file_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def load_json(cls, file_path: str | Path) -> PostInstallConfig:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return cls.from_dict(data)
