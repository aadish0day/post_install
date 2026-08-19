#!/usr/bin/env python3
"""
System and Hardware auto-detection module for post_install suite.
Identifies distribution, CPU, GPU, chassis/vendor, virtualization environment, and user setup.
"""

from __future__ import annotations

import os
import platform
import subprocess
from dataclasses import dataclass, field
from typing import List


def _sh(cmd: str) -> str:
    """Run shell command safely and return stripped stdout."""
    try:
        res = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True)
        return res.strip()
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
    virt_type: str = "none"  # none, kvm, qemu, vmware, oracle, wsl, docker, etc.

    # Session & Shell
    session_type: str = "unknown"  # x11, wayland, tty
    current_shell: str = ""


def _read_os_release() -> dict[str, str]:
    data: dict[str, str] = {}
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release", "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip().strip('"').strip("'")
    return data


def detect_system() -> SystemInfo:
    info = SystemInfo()
    info.kernel = platform.release()
    info.arch = platform.machine()
    info.hostname = platform.node()
    info.username = os.getenv("SUDO_USER") or os.getenv("USER") or os.getenv("LOGNAME") or _sh("logname") or "user"
    info.is_root = (os.geteuid() == 0) if hasattr(os, "geteuid") else False
    info.session_type = os.getenv("XDG_SESSION_TYPE") or ("wayland" if "WAYLAND_DISPLAY" in os.environ else ("x11" if "DISPLAY" in os.environ else "tty"))
    info.current_shell = os.path.basename(os.getenv("SHELL") or "/bin/bash")

    # 1. Distro Detection
    if os.path.isdir("/data/data/com.termux") or os.getenv("TERMUX_VERSION"):
        info.distro_id = "termux"
        info.distro_name = "Termux (Android)"
    else:
        os_rel = _read_os_release()
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
        with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
            cpuinfo = f.read()
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
    sys_vendor = _sh("cat /sys/class/dmi/id/sys_vendor 2>/dev/null")
    product_name = _sh("cat /sys/class/dmi/id/product_name 2>/dev/null")
    product_family = _sh("cat /sys/class/dmi/id/product_family 2>/dev/null")
    chassis_type = _sh("cat /sys/class/dmi/id/chassis_type 2>/dev/null")

    info.chassis_vendor = sys_vendor
    info.chassis_model = product_name or product_family

    combined_vendor_info = f"{sys_vendor} {product_name} {product_family}".lower()
    if any(x in combined_vendor_info for x in ["asus", "rog", "tuf", "zephyrus", "strix", "zenbook"]):
        info.is_asus = True

    # Check if laptop (chassis_type 8, 9, 10, 11, 14, 30, 31, 32 or battery presence)
    if chassis_type in {"8", "9", "10", "11", "14", "30", "31", "32"} or os.path.exists("/sys/class/power_supply/BAT0") or os.path.exists("/sys/class/power_supply/BAT1"):
        info.is_laptop = True

    # 5. Virtualization detection
    virt = _sh("systemd-detect-virt 2>/dev/null")
    info.virt_type = virt if virt else "none"

    return info


if __name__ == "__main__":
    sysinfo = detect_system()
    print(f"Distro: {sysinfo.distro_name} (ID: {sysinfo.distro_id})")
    print(f"Kernel: {sysinfo.kernel} [{sysinfo.arch}]")
    print(f"User: {sysinfo.username} (Root: {sysinfo.is_root})")
    print(f"CPU: {sysinfo.cpu_model} [{sysinfo.cpu_vendor}]")
    print(f"GPUs: {sysinfo.gpu_vendors} -> {sysinfo.gpu_descriptions}")
    print(f"Chassis: {sysinfo.chassis_model or 'Generic'} (ASUS: {sysinfo.is_asus}, Laptop: {sysinfo.is_laptop})")
    print(f"Virt: {sysinfo.virt_type}")
