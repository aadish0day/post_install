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

DISTRO_NAMES = {
    "arch": "Arch Linux",
    "debian": "Debian / Ubuntu",
    "fedora": "Fedora",
    "kali": "Kali Linux",
    "termux": "Termux",
}


@dataclass
class PostInstallConfig:
    distro: str = "arch"
    distro_name: str = "Arch Linux"
    desktop_environment: str = "kde"  # kde, tiling, none

    # Hardware & Power
    hardware_asus: bool = False
    hardware_asus_battery_limit: int = 85
    hardware_amd_gpu: bool = False
    hardware_kali_wifi: bool = False

    # Virtualization & Containers
    virt_kvm_qemu: bool = False
    virt_vmware_workstation: bool = False
    docker_enabled: bool = True

    # Dev & Pentest
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
    security_burp: bool = False
    security_kali_metapackages: list[str] = field(default_factory=list)
    security_searchsploit_update: bool = False

    # Extra Stacks
    gaming_enabled: bool = False
    ai_ml_enabled: bool = False

    # Auto-discovered extra app scripts (e.g. ["xdm", "someapp"])
    extra_scripts: list[str] = field(default_factory=list)

    # Repos & Themes
    repos_mirror_ranking: bool = True
    aur_helper: str = "paru"  # paru, yay, both, none
    repos_pacstall: bool = False
    theme_nerd_fonts: bool = True

    def set_distro(self, distro_id: str) -> None:
        self.distro = distro_id
        self.distro_name = DISTRO_NAMES.get(distro_id, distro_id.capitalize())

    @classmethod
    def default_for_system(cls, info: SystemInfo | None = None) -> PostInstallConfig:
        if info is None:
            info = detect_system()

        cfg = cls()
        cfg.distro = info.distro_id if info.distro_id != "unknown" else "arch"
        cfg.distro_name = info.distro_name

        if cfg.distro == "arch":
            cfg.desktop_environment = "kde"
            cfg.hardware_asus = info.is_asus
            cfg.hardware_amd_gpu = "amd" in info.gpu_vendors
            cfg.virt_kvm_qemu = True
            cfg.gaming_enabled = True
            cfg.ai_ml_enabled = "amd" in info.gpu_vendors and not info.virt_type.startswith("vm")
            cfg.repos_mirror_ranking = True

        elif cfg.distro == "kali":
            cfg.desktop_environment = "none"
            cfg.hardware_kali_wifi = True
            cfg.coding_enabled = False
            cfg.security_burp = True
            cfg.security_kali_metapackages = ["large"]
            cfg.security_searchsploit_update = True
            cfg.repos_mirror_ranking = False

        elif cfg.distro == "debian":
            cfg.desktop_environment = "none"
            cfg.repos_pacstall = True

        elif cfg.distro == "fedora":
            cfg.desktop_environment = "none"
            cfg.gaming_enabled = True
            cfg.repos_mirror_ranking = True

        elif cfg.distro == "termux":
            cfg.desktop_environment = "none"
            cfg.docker_enabled = False
            cfg.coding_tools = ["neovim"]
            cfg.repos_mirror_ranking = False

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
        path.write_text(json.dumps(self.to_dict(), indent=2), encoding="utf-8")

    @classmethod
    def load_json(cls, file_path: str | Path) -> PostInstallConfig:
        return cls.from_dict(json.loads(Path(file_path).read_text(encoding="utf-8")))

