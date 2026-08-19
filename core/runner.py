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

ANSI_REGEX = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[ -/]*[@-~]")


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
    requires_root: bool = False
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
                    ],
                    requires_root=True
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
                    "neovim nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra npm obs-studio p7zip pacman-contrib pacutils "
                    "papirus-icon-theme parallel pipewire pipewire-alsa pipewire-audio pipewire-jack lib32-pipewire-jack pipewire-pulse pipewire-zeroconf pipewire-libcamera "
                    "pkgfile plocate playerctl pv qalculate-qt qbittorrent ripgrep sd spandsp starship soundtouch svt-hevc tar "
                    "tree tree-sitter-cli trash-cli tmux ttf-jetbrains-mono ttf-jetbrains-mono-nerd tumbler unzip wireplumber xz "
                    "yazi yt-dlp zip zoxide zsh zstd dosfstools usbutils lazydocker opencode github-cli",
                    "if command -v git &>/dev/null && command -v git-lfs &>/dev/null; then git lfs install --skip-repo; fi"
                ],
                requires_root=True
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

            # 4. AMD GPU optimization from arch/arch.sh
            if cfg.hardware_amd_gpu:
                self.steps.append(Step(
                    step_id="arch_amd_gpu",
                    title="AMD GPU Drivers & Kernel Optimization",
                    description="Installs Mesa, Vulkan-Radeon, VA-API, and tunes GRUB for AMD P-State.",
                    commands=[
                        "sudo pacman -S --needed --noconfirm --overwrite '*' "
                        "xf86-video-amdgpu amd-ucode mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon "
                        "radeontop libva-mesa-driver lib32-libva-mesa-driver mesa-utils mesa-demos "
                        "vulkan-mesa-layers lib32-mesa-utils lib32-mesa-demos lib32-vulkan-mesa-layers glu lib32-glu",
                        'if [ -f /etc/default/grub ]; then '
                        '  sudo sed -i \'s|^GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 amd_pstate=active amd_prefcore=enable"|\' /etc/default/grub && '
                        '  sudo grub-mkconfig -o /boot/grub/grub.cfg || true; '
                        'fi'
                    ],
                    requires_root=True
                ))

            # 5. ASUS ROG Hardware & Power Tools (arch/hardware/asus.sh)
            if cfg.hardware_asus:
                asus_script = arch_dir / "hardware/asus.sh"
                self.steps.append(Step(
                    step_id="arch_asus_rog",
                    title="Configure ASUS ROG & asusctl Tooling (arch/hardware/asus.sh)",
                    description="Adds OGC repo, installs asusctl/rog-control-center, fan curves, and battery limit.",
                    commands=[f'bash "{asus_script}"'],
                    cwd=str(arch_dir),
                    requires_root=True
                ))

            # 6. Desktop Environment (arch/desktop/kde.sh or arch/desktop/tiling.sh)
            if cfg.desktop_environment == "kde":
                kde_script = arch_dir / "desktop/kde.sh"
                self.steps.append(Step(
                    step_id="arch_de_kde",
                    title="Install KDE Plasma Desktop (arch/desktop/kde.sh)",
                    description="Installs Plasma Desktop, Wayland/X11 sessions, Dolphin, Kate, and KDE apps.",
                    commands=[f'bash "{kde_script}"'],
                    cwd=str(arch_dir),
                    requires_root=True
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
                    cwd=str(arch_dir),
                    requires_root=True
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
                    cwd=str(arch_dir),
                    requires_root=True
                ))

            # 10. Coding Stack from arch/arch.sh
            if cfg.coding_enabled:
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
                    cwd=str(arch_dir),
                    requires_root=True
                ))

            # 14. Essential AUR Tools from arch/arch.sh
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

            # 15. Services and Shell Configuration from arch/arch.sh
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
                cwd=str(kali_dir),
                requires_root=True
            ))

            if cfg.security_kali_metapackages:
                pkgs = [f"kali-linux-{p}" for p in cfg.security_kali_metapackages]
                self.steps.append(Step(
                    step_id="kali_metapackages",
                    title="Install Kali Metapackages",
                    description=f"Installs selected security suites: {', '.join(pkgs)}.",
                    commands=[f"sudo nala install -y {' '.join(pkgs)}"],
                    cwd=str(kali_dir),
                    requires_root=True
                ))

            if cfg.hardware_kali_wifi:
                wifi_script = kali_dir / "hardware/wifi.sh"
                self.steps.append(Step(
                    step_id="kali_wifi_driver",
                    title="Install Realtek WiFi Driver (kali/hardware/wifi.sh)",
                    description="Compiles and loads Realtek RTL8821AU DKMS wireless driver.",
                    commands=[f'bash "{wifi_script}"'],
                    cwd=str(kali_dir),
                    requires_root=True
                ))

            if cfg.docker_enabled:
                docker_script = kali_dir / "apps/docker.sh"
                self.steps.append(Step(
                    step_id="kali_docker",
                    title="Install Docker CE on Kali (kali/apps/docker.sh)",
                    description="Configures Debian Bookworm repository for Docker CE on Kali Rolling.",
                    commands=[f'bash "{docker_script}"'],
                    cwd=str(kali_dir),
                    requires_root=True
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

        # ====================================================================
        # DEBIAN / UBUNTU WORKFLOW (STRICTLY FROM debian/ DIRECTORY)
        # ====================================================================
        elif distro == "debian":
            debian_dir = self.base_dir / "debian"
            self.steps.append(Step(
                step_id="debian_base",
                title="Debian/Ubuntu Setup (debian/debian.sh)",
                description="Installs Nala package manager, development libraries, and desktop utilities.",
                commands=[
                    "sudo apt update && sudo apt install -y nala",
                    "sudo nala update && sudo nala upgrade -y",
                    "sudo nala install -y ranger ncdu mpv maven yt-dlp gallery-dl htop fzf git git-lfs unzip nodejs flameshot xclip ueberzug highlight atool mediainfo android-tools-adb android-tools-fastboot img2pdf zathura zathura-pdf-poppler obs-studio picom nitrogen xss-lock qalculate-gtk libreoffice bluez bat alacritty jpegoptim zip tar p7zip zstd lz4 xz-utils trash-cli python3-pip",
                    "if ! command -v starship &>/dev/null; then curl -sS https://starship.rs/install.sh | sh -s -- -y; fi"
                ],
                cwd=str(debian_dir),
                requires_root=True
            ))

            if "neovim" in cfg.coding_tools:
                nvim_script = debian_dir / "apps/neovim.sh"
                self.steps.append(Step(
                    step_id="debian_neovim_source",
                    title="Compile & Install Neovim (debian/apps/neovim.sh)",
                    description="Builds Neovim from GitHub master with release optimization.",
                    commands=[f'bash "{nvim_script}"'],
                    cwd=str(debian_dir)
                ))

            if cfg.docker_enabled:
                docker_script = debian_dir / "apps/docker.sh"
                self.steps.append(Step(
                    step_id="debian_docker",
                    title="Install Docker CE & Plugins (debian/apps/docker.sh)",
                    description="Adds official Docker apt keyring and installs docker-ce, compose and buildx.",
                    commands=[f'bash "{docker_script}"'],
                    cwd=str(debian_dir),
                    requires_root=True
                ))

            if cfg.repos_pacstall:
                self.steps.append(Step(
                    step_id="debian_pacstall",
                    title="Install Pacstall Package Manager",
                    description="Installs Pacstall (AUR for Debian/Ubuntu) and ani-cli.",
                    commands=[
                        'sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)" || true',
                        'pacstall -I ani-cli-bin -P || true'
                    ],
                    cwd=str(debian_dir)
                ))

        # ====================================================================
        # FEDORA WORKFLOW (STRICTLY FROM fedora/ DIRECTORY)
        # ====================================================================
        elif distro == "fedora":
            fedora_dir = self.base_dir / "fedora"
            fedora_script = fedora_dir / "fedora.sh"
            self.steps.append(Step(
                step_id="fedora_core_setup",
                title="Fedora Optimization & RPM Fusion (fedora/fedora.sh)",
                description="Tunes DNF for parallel downloads, installs RPM Fusion, COPR starship, and dev tools.",
                commands=[f'bash "{fedora_script}"'],
                cwd=str(fedora_dir),
                requires_root=True
            ))

            if cfg.docker_enabled:
                docker_script = fedora_dir / "apps/docker.sh"
                self.steps.append(Step(
                    step_id="fedora_docker",
                    title="Install Docker CE on Fedora (fedora/apps/docker.sh)",
                    description="Configures official Docker CE repo and starts docker.service.",
                    commands=[f'bash "{docker_script}"'],
                    cwd=str(fedora_dir),
                    requires_root=True
                ))

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
                            while "\n" in buf or "\r" in buf:
                                idx_n = buf.find("\n")
                                idx_r = buf.find("\r")
                                if idx_n != -1 and (idx_r == -1 or idx_n < idx_r):
                                    line = buf[:idx_n]
                                    buf = buf[idx_n + 1:]
                                else:
                                    line = buf[:idx_r]
                                    buf = buf[idx_r + 1:]
                                clean_line = clean_output_line(line)
                                if clean_line:
                                    yield ExecutionEvent(event_type="output", step_index=idx, step=step, message=clean_line)
                        except OSError:
                            # Child closed slave
                            break
                    elif proc.poll() is not None:
                        # Drain remaining bytes
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
