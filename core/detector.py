#!/usr/bin/env python3
"""
System and Hardware auto-detection module for post_install suite.
Identifies distribution, CPU, GPU, chassis/vendor, virtualization environment, and user setup.
"""

from __future__ import annotations

import getpass
import os
import platform
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import List


def _sh(cmd: str) -> str:
    """Run shell command safely and return stripped stdout."""
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def _read_sys(path: str) -> str:
    """Safely read sysfs text file."""
    try:
        return Path(path).read_text(encoding="utf-8", errors="ignore").strip()
    except Exception:
        return ""


@dataclass
class SystemInfo:
    distro_id: str = "unknown"
    distro_name: str = "Unknown Linux"
    distro_version: str = ""
    distro_like: List[str] = field(default_factory=list)
    kernel: str = ""
    arch: str = ""
    hostname: str = ""
    username: str = ""
    is_root: bool = False

    # Hardware details
    cpu_vendor: str = "unknown"  # amd, intel, arm, other
    cpu_model: str = ""
    gpu_vendors: List[str] = field(default_factory=list)  # amd, nvidia, intel, other
    gpu_descriptions: List[str] = field(default_factory=list)
    chassis_vendor: str = ""
    chassis_model: str = ""
    is_asus: bool = False
    is_laptop: bool = False

    # Virtualization
    virt_type: str = "none"

    # Session & Shell
    session_type: str = "unknown"
    current_shell: str = ""


def _get_os_release() -> dict[str, str]:
    if hasattr(platform, "freedesktop_os_release"):
        try:
            return platform.freedesktop_os_release()
        except OSError:
            pass
    return {}


def detect_system() -> SystemInfo:
    info = SystemInfo()
    info.kernel = platform.release()
    info.arch = platform.machine()
    info.hostname = platform.node()
    info.username = os.getenv("SUDO_USER") or os.getenv("USER") or getpass.getuser()
    info.is_root = (os.geteuid() == 0) if hasattr(os, "geteuid") else False
    info.session_type = os.getenv("XDG_SESSION_TYPE") or ("wayland" if "WAYLAND_DISPLAY" in os.environ else ("x11" if "DISPLAY" in os.environ else "tty"))
    info.current_shell = os.path.basename(os.getenv("SHELL") or "/bin/bash")

    # 1. Distro Detection
    if os.path.isdir("/data/data/com.termux") or os.getenv("TERMUX_VERSION"):
        info.distro_id = "termux"
        info.distro_name = "Termux (Android)"
    else:
        os_rel = _get_os_release()
        raw_id = os_rel.get("ID", "").lower()
        id_like = [x.lower() for x in os_rel.get("ID_LIKE", "").split()]
        info.distro_version = os_rel.get("VERSION_ID", "")
        info.distro_name = os_rel.get("PRETTY_NAME", os_rel.get("NAME", "Linux"))
        info.distro_like = id_like

        if raw_id == "kali":
            info.distro_id = "kali"
        elif raw_id in {"arch", "manjaro", "endeavouros", "garuda", "artix", "cachyos"} or "arch" in id_like:
            info.distro_id = "arch"
        elif raw_id in {"fedora", "rhel", "centos", "rocky", "almalinux", "nobara"} or "fedora" in id_like or "rhel" in id_like:
            info.distro_id = "fedora"
        elif raw_id in {"debian", "ubuntu", "pop", "linuxmint", "elementary", "raspbian"} or "debian" in id_like or "ubuntu" in id_like:
            info.distro_id = "debian"
        else:
            info.distro_id = raw_id or "unknown"

    # 2. CPU Detection
    try:
        cpuinfo = Path("/proc/cpuinfo").read_text(encoding="utf-8", errors="ignore")
        if "GenuineIntel" in cpuinfo:
            info.cpu_vendor = "intel"
        elif "AuthenticAMD" in cpuinfo:
            info.cpu_vendor = "amd"
        elif "ARM" in cpuinfo or "aarch64" in info.arch:
            info.cpu_vendor = "arm"
        else:
            info.cpu_vendor = "other"

        for line in cpuinfo.splitlines():
            if "model name" in line:
                info.cpu_model = line.split(":", 1)[1].strip()
                break
    except Exception:
        pass

    # 3. GPU Detection via lspci
    lspci_out = _sh("lspci 2>/dev/null | grep -Ei 'vga|3d controller|display'")
    if lspci_out:
        for line in lspci_out.splitlines():
            desc = line.split(":", 2)[-1].strip() if ":" in line else line
            info.gpu_descriptions.append(desc)
            line_low = line.lower()
            if "nvidia" in line_low and "nvidia" not in info.gpu_vendors:
                info.gpu_vendors.append("nvidia")
            if any(x in line_low for x in ["amd", "ati", "radeon", "navi", "rembrandt", "renoir"]) and "amd" not in info.gpu_vendors:
                info.gpu_vendors.append("amd")
            if "intel" in line_low and "intel" not in info.gpu_vendors:
                info.gpu_vendors.append("intel")
            if any(x in line_low for x in ["vmware", "qemu", "virtio", "virtualbox"]) and "virtual" not in info.gpu_vendors:
                info.gpu_vendors.append("virtual")

    # 4. Chassis / Laptop / Vendor detection
    sys_vendor = _read_sys("/sys/class/dmi/id/sys_vendor")
    product_name = _read_sys("/sys/class/dmi/id/product_name")
    product_family = _read_sys("/sys/class/dmi/id/product_family")
    chassis_type = _read_sys("/sys/class/dmi/id/chassis_type")

    info.chassis_vendor = sys_vendor
    info.chassis_model = product_name or product_family

    combined = f"{sys_vendor} {product_name} {product_family}".lower()
    info.is_asus = any(x in combined for x in ["asus", "rog", "tuf", "zephyrus", "strix", "zenbook"])

    if chassis_type in {"8", "9", "10", "11", "14", "30", "31", "32"} or os.path.exists("/sys/class/power_supply/BAT0") or os.path.exists("/sys/class/power_supply/BAT1"):
        info.is_laptop = True

    # 5. Virtualization detection
    info.virt_type = _sh("systemd-detect-virt 2>/dev/null") or "none"

    return info

