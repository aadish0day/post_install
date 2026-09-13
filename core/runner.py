#!/usr/bin/env python3
"""
Execution engine for the post-installation plan.
Transforms PostInstallConfig into an ordered sequence of discrete, inspectable steps
strictly from the selected distribution's folder and modular scripts.
"""

from __future__ import annotations

import os
import pty
import re
import select
import subprocess
import time
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from core.config import PostInstallConfig
from core.detector import SystemInfo, detect_system

ANSI_REGEX = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[ -/]*[@-~]|[\x00-\x08\x0e-\x1f]")

# Scripts in apps/ already handled by dedicated config flags / steps, per distro.
# Any .sh file NOT in the distro's set gets auto-discovered as an optional extra.
_MANAGED_APP_SCRIPTS: dict[str, set[str]] = {
    "arch": {"docker.sh", "gaming.sh", "paru.sh", "yay.sh"},
    "kali": {"docker.sh"},
    "debian": {"docker.sh", "neovim.sh", "coding.sh", "gaming.sh", "aiml.sh", "productivity.sh"},
    "fedora": {"docker.sh", "coding.sh", "gaming.sh", "aiml.sh", "productivity.sh"},
    "termux": set(),
}
_MANAGED_APP_DIRS = {"burp"}


def discover_extra_scripts(base_dir: Path, distro: str) -> list[str]:
    """Scan <distro>/apps/ for .sh scripts not managed by hardcoded steps.

    Returns a sorted list of script stems (e.g. ["xdm", "someapp"]).
    """
    apps_dir = base_dir / distro / "apps"
    if not apps_dir.is_dir():
        return []
    managed = _MANAGED_APP_SCRIPTS.get(distro, set())
    found = []
    for entry in apps_dir.iterdir():
        if entry.is_file() and entry.suffix == ".sh" and entry.name not in managed:
            found.append(entry.stem)
        # skip managed subdirs like burp/
    return sorted(found)


def clean_output_line(raw_line: str) -> str:
    """Strips ANSI escapes, OSC sequences, and orphaned shell-integration metadata."""
    cleaned = ANSI_REGEX.sub("", raw_line).strip()
    if cleaned.startswith(("3008;", "133;", "633;", "777;", "1337;")):
        return ""
    return cleaned


class StepStatus(Enum):
    PENDING = auto()
    RUNNING = auto()
    COMPLETED = auto()
    FAILED = auto()
    SKIPPED = auto()


@dataclass
class Step:
    step_id: str
    title: str
    description: str
    commands: List[str] = field(default_factory=list)
    cwd: Optional[str] = None
    status: StepStatus = StepStatus.PENDING
    error_message: Optional[str] = None
    duration: float = 0.0


@dataclass
class ExecutionEvent:
    event_type: str  # "step_start", "output", "step_complete", "step_fail", "plan_complete"
    step_index: int
    step: Step
    message: str = ""
    timestamp: float = field(default_factory=time.time)
    is_transient: bool = False


class ExecutionPlan:
    def __init__(self, config: PostInstallConfig, base_dir: Path, sysinfo: Optional[SystemInfo] = None):
        self.config = config
        self.base_dir = base_dir.resolve()
        self.sysinfo = sysinfo or detect_system()
        self.steps: List[Step] = []
        self._build_plan()

    def _build_plan(self) -> None:
        cfg = self.config
        distro = cfg.distro

        # ====================================================================
        # ARCH LINUX WORKFLOW (STRICTLY FROM arch/ DIRECTORY)
        # ====================================================================
        if distro == "arch":
            arch_dir = self.base_dir / "arch"

            # 1. Mirror optimization (Reflector)
            if cfg.repos_mirror_ranking:
                self.steps.append(Step(
                    step_id="arch_mirrors",
                    title="Optimize Mirrorlist (Reflector India)",
                    description="Ranks the fastest HTTPS mirrors strictly in India with timeout protection.",
                    commands=[
                        "sudo pacman -Sy --noconfirm",
                        "sudo pacman -S --needed reflector --noconfirm --overwrite '*'",
                        "timeout 30s sudo reflector --latest 10 --fastest 5 --protocol https --connection-timeout 5 --download-timeout 5 --threads 8 --country India --sort rate --save /etc/pacman.d/mirrorlist || echo 'Reflector timed out or failed; keeping existing mirrorlist.'",
                        "sudo pacman -Syu --noconfirm --overwrite '*'"
                    ]
                ))

            # 2. Base packages & terminal stack from arch/arch.sh
            self.steps.append(Step(
                step_id="arch_base_packages",
                title="Install Arch Base Packages & Utilities",
                description="Installs core CLI tools, fonts, sound, and utilities from arch/arch.sh.",
                commands=[
                    "sudo pacman -S --needed --noconfirm --overwrite '*' "
                    "android-tools aria2 atool bat cantarell-fonts chromaprint doxygen duf fastfetch fd ffmpegthumbnailer "
                    "fluidsynth fzf gcc gettext git git-lfs gst-libav gst-plugins-ugly gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs "
                    "gvfs-smb highlight htop img2pdf imagemagick inxi jq jpegoptim kitty less libavtp libdca libgme liblrdf libltc "
                    "libtool linux-headers lsd lz4 make man-db man-pages maven mediainfo mjpegtools mkinitcpio mpv mpv-mpris ncdu "
                    "neovim nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra npm obs-studio 7zip pacman-contrib pacutils "
                    "papirus-icon-theme parallel pipewire pipewire-alsa pipewire-audio pipewire-jack lib32-pipewire-jack pipewire-pulse pipewire-zeroconf pipewire-libcamera "
                    "pkgfile plocate playerctl pv qalculate-qt qbittorrent ripgrep sd spandsp starship soundtouch svt-hevc tar "
                    "tree tree-sitter-cli trash-cli tmux ttf-jetbrains-mono ttf-jetbrains-mono-nerd tumbler unzip wireplumber xz "
                    "yazi yt-dlp zip zoxide zsh zstd dosfstools usbutils lazydocker opencode github-cli",
                    "if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then git lfs install --skip-repo; fi"
                ]
            ))

            # 3. AUR Helper(s) (arch/apps/paru.sh & arch/apps/yay.sh)
            if cfg.aur_helper in ("paru", "both"):
                paru_script = arch_dir / "apps/paru.sh"
                self.steps.append(Step(
                    step_id="arch_paru",
                    title="Install Paru AUR Helper (arch/apps/paru.sh)",
                    description="Installs Paru AUR Helper with paru-bin fallback support.",
                    commands=[f'bash "{paru_script}"'],
                    cwd=str(arch_dir)
                ))
            if cfg.aur_helper in ("yay", "both"):
                yay_script = arch_dir / "apps/yay.sh"
                self.steps.append(Step(
                    step_id="arch_yay",
                    title="Install Yay AUR Helper (arch/apps/yay.sh)",
                    description="Installs Yay AUR Helper with yay-bin fallback support.",
                    commands=[f'bash "{yay_script}"'],
                    cwd=str(arch_dir)
                ))

            # 4. CPU/GPU vendor drivers (arch/hardware/gpu/amd.sh, nvidia.sh, intel.sh)
            if cfg.hardware_amd_gpu:
                amd_script = arch_dir / "hardware/gpu/amd.sh"
                self.steps.append(Step(
                    step_id="arch_amd_gpu",
                    title="AMD CPU/GPU Drivers & Kernel Optimization (arch/hardware/gpu/amd.sh)",
                    description="Installs amd-ucode, Mesa, Vulkan-Radeon, VA-API, and tunes GRUB for AMD P-State."
                                + (" Also installs AMD Pro AUR packages (AMF, OpenCL, OGLP)." if cfg.hardware_amd_pro else ""),
                    commands=[f'bash "{amd_script}"' + (" --pro" if cfg.hardware_amd_pro else "")],
                    cwd=str(arch_dir)
                ))
            if cfg.hardware_intel_gpu:
                intel_script = arch_dir / "hardware/gpu/intel.sh"
                self.steps.append(Step(
                    step_id="arch_intel_gpu",
                    title="Intel CPU/GPU Drivers (arch/hardware/gpu/intel.sh)",
                    description="Installs intel-ucode, Mesa, Vulkan-Intel, and intel-media-driver.",
                    commands=[f'bash "{intel_script}"'],
                    cwd=str(arch_dir)
                ))
            if cfg.hardware_nvidia_gpu:
                nvidia_script = arch_dir / "hardware/gpu/nvidia.sh"
                self.steps.append(Step(
                    step_id="arch_nvidia_gpu",
                    title="NVIDIA GPU Drivers (arch/hardware/gpu/nvidia.sh)",
                    description="Installs nvidia-open-dkms, nvidia-utils, laptop power config, and suspend services.",
                    commands=[f'bash "{nvidia_script}"'],
                    cwd=str(arch_dir)
                ))

            # 5. ASUS ROG Hardware & Power Tools (arch/hardware/asus.sh)
            if cfg.hardware_asus:
                asus_script = arch_dir / "hardware/asus.sh"
                self.steps.append(Step(
                    step_id="arch_asus_rog",
                    title="Configure ASUS ROG & asusctl Tooling (arch/hardware/asus.sh)",
                    description="Installs asusctl/rog-control-center, fan curves, and battery limit.",
                    commands=[f'bash "{asus_script}" {int(cfg.hardware_asus_battery_limit)}'],
                    cwd=str(arch_dir)
                ))

            # 6. Desktop Environment (arch/desktop/kde.sh or arch/desktop/tiling.sh)
            if cfg.desktop_environment == "kde":
                kde_script = arch_dir / "desktop/kde.sh"
                self.steps.append(Step(
                    step_id="arch_de_kde",
                    title="Install KDE Plasma Desktop (arch/desktop/kde.sh)",
                    description="Installs Plasma Desktop, Wayland/X11 sessions, Dolphin, Kate, and KDE apps.",
                    commands=[f'bash "{kde_script}"'],
                    cwd=str(arch_dir)
                ))
            elif cfg.desktop_environment == "tiling":
                tiling_script = arch_dir / "desktop/tiling.sh"
                self.steps.append(Step(
                    step_id="arch_de_tiling",
                    title="Install X11 Tiling Window Manager & Touchpad (arch/desktop/tiling.sh)",
                    description="Installs Polybar, Picom, Rofi, Dunst, Feh, Zathura, i3lock-color, Dracula GTK, and configures X11 touchpad.",
                    commands=[f'bash "{tiling_script}"'],
                    cwd=str(arch_dir)
                ))

            # 8. Virtualization (arch/virt/kvm-qemu.sh & arch/virt/vmware-workstation.sh)
            if cfg.virt_kvm_qemu:
                kvm_script = arch_dir / "virt/kvm-qemu.sh"
                self.steps.append(Step(
                    step_id="arch_virt_kvm",
                    title="Setup KVM, QEMU & virt-manager (arch/virt/kvm-qemu.sh)",
                    description="Installs QEMU desktop, virt-manager, libvirt network bridge and user groups.",
                    commands=[f'bash "{kvm_script}"'],
                    cwd=str(arch_dir)
                ))

            if cfg.virt_vmware_workstation:
                vmware_script = arch_dir / "virt/vmware-workstation.sh"
                self.steps.append(Step(
                    step_id="arch_virt_vmware",
                    title="Install VMware Workstation (arch/virt/vmware-workstation.sh)",
                    description="Compiles VMware kernel modules and enables network and USB services.",
                    commands=[f'bash "{vmware_script}"'],
                    cwd=str(arch_dir)
                ))

            # 9. Docker Containerization (arch/apps/docker.sh)
            if cfg.docker_enabled:
                docker_script = arch_dir / "apps/docker.sh"
                self.steps.append(Step(
                    step_id="arch_docker",
                    title="Install Docker Engine & Buildx (arch/apps/docker.sh)",
                    description="Installs Docker, Docker Compose, Buildx, enables service and adds user to docker group.",
                    commands=[f'bash "{docker_script}"'],
                    cwd=str(arch_dir)
                ))

            # 10. Coding Stack from arch/arch.sh
            if cfg.coding_enabled and cfg.aur_helper != "none":
                self.steps.append(Step(
                    step_id="arch_coding_aur",
                    title="Install Developer & Coding Suite (AUR)",
                    description="Installs VS Code, Cursor, Android Studio, Flutter SDK, and Antigravity tooling.",
                    commands=[
                        "if command -v paru &>/dev/null; then "
                        "  paru -S --needed --noconfirm visual-studio-code-bin cursor-bin android-studio flutter-bin antigravity-cli antigravity-ide || true; "
                        "elif command -v yay &>/dev/null; then "
                        "  yay -S --needed --noconfirm visual-studio-code-bin cursor-bin android-studio flutter-bin antigravity-cli antigravity-ide || true; "
                        "fi"
                    ],
                    cwd=str(arch_dir)
                ))

            # 11. Security / Burp Suite Pro (arch/apps/burp/install.sh)
            if cfg.security_burp:
                burp_script = arch_dir / "apps/burp/install.sh"
                self.steps.append(Step(
                    step_id="arch_burp_pro",
                    title="Setup Burp Suite Professional (arch/apps/burp/install.sh)",
                    description="Installs OpenJDK 21, downloads Burp Pro latest, creates launcher script and desktop entry.",
                    commands=[f'bash "{burp_script}"'],
                    cwd=str(arch_dir)
                ))

            # 12. Gaming packages (arch/apps/gaming.sh)
            if cfg.gaming_enabled:
                gaming_script = arch_dir / "apps/gaming.sh"
                self.steps.append(Step(
                    step_id="arch_gaming",
                    title="Setup Gaming Stack (arch/apps/gaming.sh)",
                    description="Installs Wine-Staging, Winetricks, Lutris, GameMode, DXVK async, and 32-bit runtimes.",
                    commands=[f'bash "{gaming_script}"'],
                    cwd=str(arch_dir)
                ))

            # 13. AI / ML Stack from arch/arch.sh
            if cfg.ai_ml_enabled:
                self.steps.append(Step(
                    step_id="arch_aiml",
                    title="Install ROCm & AI/ML Acceleration Suite",
                    description="Installs ROCm SDK, PyTorch ROCm, and ONNX Runtime ROCm.",
                    commands=[
                        "sudo pacman -S --needed --noconfirm --overwrite '*' "
                        "rocm-llvm rocm-opencl-runtime rocm-opencl-sdk rocm-hip-sdk rocm-ml-libraries "
                        "rocm-openmp hipify-clang rocminfo opencl-headers libclc ocl-icd python-pytorch-rocm python-onnxruntime-rocm"
                    ],
                    cwd=str(arch_dir)
                ))

            # 14. Essential AUR Tools from arch/arch.sh
            if cfg.aur_helper != "none":
                self.steps.append(Step(
                    step_id="arch_general_aur",
                    title="Install Essential AUR Productivity Tools",
                    description="Installs AnyDesk, LocalSend, Thorium, Zen Browser, Vesktop, and gallery-dl.",
                    commands=[
                        "if command -v paru &>/dev/null; then "
                        "  paru -S --needed --noconfirm advcpmv ani-cli anydesk-bin gallery-dl-bin localsend-bin markitdown-bin thorium-browser-bin vesktop-bin zen-browser-bin || true; "
                        "elif command -v yay &>/dev/null; then "
                        "  yay -S --needed --noconfirm advcpmv ani-cli anydesk-bin gallery-dl-bin localsend-bin markitdown-bin thorium-browser-bin vesktop-bin zen-browser-bin || true; "
                        "fi"
                    ],
                    cwd=str(arch_dir)
                ))

            # 15. Auto-discovered extra app scripts from arch/apps/
            self._append_extra_scripts_steps(arch_dir, "arch")

            # 16. Services and Shell Configuration from arch/arch.sh
            self.steps.append(Step(
                step_id="arch_services_shell",
                title="Configure Services & Default Shell (arch/arch.sh)",
                description="Starts xdg-desktop-portal services and sets default shell to Zsh.",
                commands=[
                    "for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do "
                    "  if systemctl --user list-unit-files | grep -q \"$s\"; then "
                    "    systemctl --user start \"$s\" 2>/dev/null || true; "
                    "  fi; "
                    "done",
                    'if [ "$SHELL" != "$(command -v zsh 2>/dev/null || echo "")" ] && command -v zsh &>/dev/null; then '
                    '  chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true; '
                    'fi'
                ],
                cwd=str(arch_dir)
            ))

        # ====================================================================
        # KALI LINUX WORKFLOW (STRICTLY FROM kali/ DIRECTORY)
        # ====================================================================
        elif distro == "kali":
            kali_dir = self.base_dir / "kali"
            self.steps.append(Step(
                step_id="kali_core_setup",
                title="Kali Linux Core Setup (kali/kali.sh)",
                description="Installs Nala, base tools, creates ~/cybersec, and links dotfiles.",
                commands=[
                    "sudo apt update && sudo apt install -y nala",
                    "sudo nala update && sudo nala upgrade -y",
                    "sudo nala install -y git git-lfs stow zsh tmux curl wget vim neovim fzf zoxide lsd trash-cli htop open-vm-tools starship",
                    'mkdir -p ~/cybersec',
                    'if [ ! -d ~/dotfile ]; then git clone https://github.com/aadish0day/dotfile.git ~/dotfile && (cd ~/dotfile && [ -f link.sh ] && ./link.sh || true); fi'
                ],
                cwd=str(kali_dir)
            ))

            if cfg.security_kali_metapackages:
                pkgs = [f"kali-linux-{p}" for p in cfg.security_kali_metapackages]
                self.steps.append(Step(
                    step_id="kali_metapackages",
                    title="Install Kali Metapackages",
                    description=f"Installs selected security suites: {', '.join(pkgs)}.",
                    commands=[f"sudo nala install -y {' '.join(pkgs)}"],
                    cwd=str(kali_dir)
                ))

            if cfg.hardware_kali_wifi:
                wifi_script = kali_dir / "hardware/wifi.sh"
                self.steps.append(Step(
                    step_id="kali_wifi_driver",
                    title="Install Realtek WiFi Driver (kali/hardware/wifi.sh)",
                    description="Compiles and loads Realtek RTL8821AU DKMS wireless driver.",
                    commands=[f'bash "{wifi_script}"'],
                    cwd=str(kali_dir)
                ))

            if cfg.docker_enabled:
                docker_script = kali_dir / "apps/docker.sh"
                self.steps.append(Step(
                    step_id="kali_docker",
                    title="Install Docker CE on Kali (kali/apps/docker.sh)",
                    description="Configures Debian Bookworm repository for Docker CE on Kali Rolling.",
                    commands=[f'bash "{docker_script}"'],
                    cwd=str(kali_dir)
                ))

            if cfg.security_burp:
                burp_script = kali_dir / "apps/burp/install.sh"
                self.steps.append(Step(
                    step_id="kali_burp_pro",
                    title="Setup Burp Suite Professional (kali/apps/burp/install.sh)",
                    description="Installs Java 21, downloads Burp Pro latest, creates launcher script and desktop entry.",
                    commands=[f'bash "{burp_script}"'],
                    cwd=str(kali_dir)
                ))

            if cfg.security_searchsploit_update:
                self.steps.append(Step(
                    step_id="kali_searchsploit",
                    title="Update SearchSploit Exploit Database",
                    description="Fetches latest exploit-database archive updates.",
                    commands=["if command -v searchsploit &>/dev/null; then searchsploit -u || true; fi"],
                    cwd=str(kali_dir)
                ))

            # Auto-discovered extra app scripts from kali/apps/
            self._append_extra_scripts_steps(kali_dir, "kali")

        # ====================================================================
        # DEBIAN / UBUNTU & FEDORA WORKFLOWS (modular layout mirroring arch/)
        # ====================================================================
        elif distro in ("debian", "fedora"):
            self._append_modular_steps(distro)

        # ====================================================================
        # TERMUX WORKFLOW (STRICTLY FROM termux/ DIRECTORY)
        # ====================================================================
        elif distro == "termux":
            termux_dir = self.base_dir / "termux"
            termux_script = termux_dir / "termux.sh"
            self.steps.append(Step(
                step_id="termux_core_setup",
                title="Termux Environment Setup (termux/termux.sh)",
                description="Updates packages, configures storage permissions, installs zsh, tmux, and dotfiles.",
                commands=[f'bash "{termux_script}"'],
                cwd=str(termux_dir)
            ))

            if cfg.theme_nerd_fonts:
                font_script = termux_dir / "system/font.sh"
                self.steps.append(Step(
                    step_id="termux_font",
                    title="Install JetBrains Mono Nerd Font (termux/system/font.sh)",
                    description="Downloads and sets ~/.termux/font.ttf from GitHub releases.",
                    commands=[f'bash "{font_script}"'],
                    cwd=str(termux_dir)
                ))

            # Auto-discovered extra app scripts from termux/apps/
            self._append_extra_scripts_steps(termux_dir, "termux")

    def _append_modular_steps(self, distro: str) -> None:
        """Debian/Fedora plan: same module order as arch/, scripts under <distro>/."""
        cfg = self.config
        d = self.base_dir / distro
        label = {"debian": "Debian/Ubuntu", "fedora": "Fedora"}[distro]

        def add(step_id: str, rel: str, title: str, description: str, args: str = "") -> None:
            script = d / rel
            self.steps.append(Step(
                step_id=f"{distro}_{step_id}",
                title=f"{title} ({distro}/{rel})",
                description=description,
                commands=[f'bash "{script}"' + (f" {args}" if args else "")],
                cwd=str(d)
            ))

        # 1. Package manager & repositories
        if distro == "fedora":
            add("dnf", "system/dnf.sh", "Optimize DNF", "Parallel downloads, fastest mirror and sane defaults for dnf5.")
            add("repos", "system/repos.sh", "Enable RPM Fusion, COPR & Codecs", "RPM Fusion free/nonfree, COPR repos and full ffmpeg codecs.")
        else:
            add("repos", "system/repos.sh", "Enable contrib/non-free & i386", "Enables contrib, non-free, non-free-firmware (universe/multiverse on Ubuntu), i386 and nala.")

        # 2. Extra package sources (AUR-like helpers)
        if distro == "debian" and cfg.repos_pacstall:
            add("pacstall", "system/pacstall.sh", "Install Pacstall (AUR for Debian)", "Installs Pacstall, used for apps not packaged in Debian.")
        if cfg.repos_flatpak:
            add("flatpak", "system/flatpak.sh", "Setup Flatpak & Flathub", "Installs Flatpak and adds the Flathub remote.")

        # 3. Base packages
        add("base_packages", "system/base.sh", f"Install {label} Base Packages & Utilities",
            "Core CLI tools, fonts, sound, and utilities matching the Arch base set.")

        # 4. CPU/GPU vendor drivers & ASUS tools
        if cfg.hardware_amd_gpu:
            add("amd_gpu", "hardware/gpu/amd.sh", "AMD CPU/GPU Drivers & Kernel Optimization",
                "Installs AMD microcode, firmware, Mesa Vulkan/VA-API, and amd_pstate kernel args.")
        if cfg.hardware_intel_gpu:
            add("intel_gpu", "hardware/gpu/intel.sh", "Intel CPU/GPU Drivers", "Installs Intel microcode, media driver, and Mesa Vulkan.")
        if cfg.hardware_nvidia_gpu:
            add("nvidia_gpu", "hardware/gpu/nvidia.sh", "NVIDIA GPU Drivers", "Installs the NVIDIA driver, power management config, and suspend services.")
        if cfg.hardware_asus:
            add("asus_rog", "hardware/asus.sh", "Configure ASUS ROG & asusctl Tooling",
                "Installs asusctl/rog-control-center, fan curves, and battery limit.", str(int(cfg.hardware_asus_battery_limit)))

        # 5. Desktop environment
        if cfg.desktop_environment == "kde":
            add("de_kde", "desktop/kde.sh", "Install KDE Plasma Desktop", "Installs Plasma Desktop, SDDM, Dolphin, Kate, and KDE apps.")
        elif cfg.desktop_environment == "tiling":
            add("de_tiling", "desktop/tiling.sh", "Install X11 Tiling Window Manager & Touchpad",
                "Installs Polybar, Picom, Rofi, Dunst, Feh, Zathura, i3lock-color, Dracula GTK, and configures X11 touchpad.")

        # 6. Virtualization
        if cfg.virt_kvm_qemu:
            add("virt_kvm", "virt/kvm-qemu.sh", "Setup KVM, QEMU & virt-manager", "Installs QEMU/KVM, libvirt, virt-manager, UEFI firmware and user groups.")
        if cfg.virt_vmware_workstation:
            add("virt_vmware", "virt/vmware-workstation.sh", "Install VMware Workstation",
                "Installs build dependencies and runs a downloaded VMware Workstation bundle.")

        # 7. Docker
        if cfg.docker_enabled:
            add("docker", "apps/docker.sh", "Install Docker CE & Plugins", "Official Docker CE repo, Compose and Buildx, docker group.")

        # 8. Developer tools
        if cfg.coding_enabled and cfg.coding_tools:
            add("coding", "apps/coding.sh", "Install Developer & Coding Suite",
                f"Installs: {', '.join(cfg.coding_tools)}.", " ".join(cfg.coding_tools))

        # 9. Gaming
        if cfg.gaming_enabled:
            add("gaming", "apps/gaming.sh", "Setup Gaming Stack", "Wine, Winetricks, Steam, Lutris, GameMode, MangoHud, and umu-launcher.")

        # 10. AI / ML
        if cfg.ai_ml_enabled:
            add("aiml", "apps/aiml.sh", "Install ROCm & AI/ML Acceleration Suite", "Installs ROCm runtime tools and PyTorch ROCm in ~/.venvs/rocm.")

        # 11. Productivity apps (Arch AUR list equivalents)
        if cfg.productivity_enabled:
            add("productivity", "apps/productivity.sh", "Install Essential Productivity Apps",
                "AnyDesk, LocalSend, Thorium, Zen Browser, Vesktop, Obsidian, ani-cli, gallery-dl, and markitdown.")

        # 12. Auto-discovered extra app scripts
        self._append_extra_scripts_steps(d, distro)

        # 13. Shell & services
        add("services_shell", "system/shell.sh", "Configure Services & Default Shell", "Starts xdg-desktop-portal services and sets default shell to Zsh.")

    def _append_extra_scripts_steps(self, distro_dir: Path, distro_name: str) -> None:
        if self.config.extra_scripts:
            apps_dir = distro_dir / "apps"
            if not apps_dir.is_dir():
                return
            managed = _MANAGED_APP_SCRIPTS.get(distro_name, set())
            for script_name in sorted(self.config.extra_scripts):
                script_path = apps_dir / f"{script_name}.sh"
                if script_path.is_file() and script_path.name not in managed:
                    nice_name = script_name.replace("_", " ").replace("-", " ").title()
                    self.steps.append(Step(
                        step_id=f"{distro_name}_extra_{script_name}",
                        title=f"Install {nice_name} ({distro_name}/apps/{script_name}.sh)",
                        description=f"Auto-discovered script: {distro_name}/apps/{script_name}.sh",
                        commands=[f'bash "{script_path}"'],
                        cwd=str(distro_dir)
                    ))


def run_plan(plan: ExecutionPlan, dry_run: bool = False) -> Generator[ExecutionEvent, None, None]:
    """Execute the plan yielding progress events for TUI or CLI consumers."""
    total_steps = len(plan.steps)

    for idx, step in enumerate(plan.steps):
        step.status = StepStatus.RUNNING
        start_t = time.time()
        yield ExecutionEvent(event_type="step_start", step_index=idx, step=step, message=f"Starting: {step.title}")

        if dry_run:
            for cmd in step.commands:
                time.sleep(0.06)
                yield ExecutionEvent(event_type="output", step_index=idx, step=step, message=f"[DRY-RUN] Would execute: {cmd}")
            step.status = StepStatus.COMPLETED
            step.duration = time.time() - start_t
            yield ExecutionEvent(event_type="step_complete", step_index=idx, step=step, message=f"Completed (dry-run): {step.title}")
            continue

        failed = False
        error_lines = []

        for cmd in step.commands:
            yield ExecutionEvent(event_type="output", step_index=idx, step=step, message=f"[EXEC] {cmd}")
            master_fd = None
            try:
                master_fd, slave_fd = pty.openpty()
                proc = subprocess.Popen(
                    cmd,
                    shell=True,
                    executable="/bin/bash",
                    cwd=step.cwd or str(plan.base_dir),
                    stdin=slave_fd,
                    stdout=slave_fd,
                    stderr=slave_fd,
                    close_fds=True
                )
                os.close(slave_fd)  # Close slave in parent so EOF is detectable

                buf = ""
                while True:
                    r, _, _ = select.select([master_fd], [], [], 0.03)
                    if r:
                        try:
                            data = os.read(master_fd, 2048)
                            if not data:
                                break
                            buf += data.decode("utf-8", errors="replace")
                            lines = buf.splitlines(keepends=True)
                            if lines and not (lines[-1].endswith("\n") or lines[-1].endswith("\r")):
                                buf = lines.pop()
                            else:
                                buf = ""
                            for line in lines:
                                is_transient = line.endswith("\r") and not line.endswith("\n")
                                clean_line = clean_output_line(line)
                                if clean_line:
                                    yield ExecutionEvent(
                                        event_type="output",
                                        step_index=idx,
                                        step=step,
                                        message=clean_line,
                                        is_transient=is_transient,
                                    )
                        except OSError:
                            break
                    elif proc.poll() is not None:
                        try:
                            data = os.read(master_fd, 4096)
                            if data:
                                buf += data.decode("utf-8", errors="replace")
                        except Exception:
                            pass
                        break

                for chunk in re.split(r'[\r\n]+', buf):
                    clean_chunk = clean_output_line(chunk)
                    if clean_chunk:
                        yield ExecutionEvent(event_type="output", step_index=idx, step=step, message=clean_chunk)

                ret = proc.wait()
                if ret != 0:
                    failed = True
                    error_lines.append(f"Command failed with exit code {ret}: {cmd}")
                    break
            except Exception as e:
                failed = True
                error_lines.append(str(e))
                break
            finally:
                if master_fd is not None:
                    try:
                        os.close(master_fd)
                    except OSError:
                        pass

        step.duration = time.time() - start_t

        if failed:
            step.status = StepStatus.FAILED
            step.error_message = "\n".join(error_lines)
            yield ExecutionEvent(event_type="step_fail", step_index=idx, step=step, message=f"Failed: {step.title} ({step.error_message})")
        else:
            step.status = StepStatus.COMPLETED
            yield ExecutionEvent(event_type="step_complete", step_index=idx, step=step, message=f"Success: {step.title}")

    yield ExecutionEvent(event_type="plan_complete", step_index=total_steps - 1, step=plan.steps[-1], message="All steps finished.")
