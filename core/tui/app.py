#!/usr/bin/env python3
"""
Main TUI Application controller for the post-installation suite.
Provides the entry point for curses.wrapper and orchestrates the user interaction flow.
"""

from __future__ import annotations

import curses
import os
import sys
from pathlib import Path
from typing import Optional

from core.config import PostInstallConfig
from core.detector import SystemInfo, detect_system
from core.runner import ExecutionPlan
from core.tui.colors import Colors
from core.tui.screens import ConfirmScreen, ExecutionScreen, GlobalMenuScreen


class PostInstallTUI:
    def __init__(
        self,
        base_dir: Optional[Path] = None,
        config_path: Optional[str] = None,
        dry_run: bool = False,
        distro_override: Optional[str] = None
    ):
        self.base_dir = base_dir or Path(__file__).resolve().parent.parent.parent
        self.config_path = config_path
        self.dry_run = dry_run
        self.distro_override = distro_override

    def start(self, stdscr: curses.window) -> int:
        """Main Curses entry point invoked by curses.wrapper."""
        Colors.init()
        curses.curs_set(0)

        # 1. System auto-detection
        sysinfo = detect_system()

        # 2. Configuration initialization
        if self.config_path and os.path.isfile(self.config_path):
            config = PostInstallConfig.load_json(self.config_path)
        else:
            config = PostInstallConfig.default_for_system(sysinfo)

        if self.distro_override:
            config.distro = self.distro_override
            names = {
                "arch": "Arch Linux",
                "debian": "Debian / Ubuntu",
                "fedora": "Fedora",
                "kali": "Kali Linux",
                "termux": "Termux"
            }
            config.distro_name = names.get(self.distro_override, self.distro_override.capitalize())

        # 3. Main Global Menu loop
        while True:
            menu = GlobalMenuScreen(stdscr, config, sysinfo)
            action = menu.run()

            if action == "exit" or action is None:
                return 0

            elif action == "install":
                # Build execution plan
                plan = ExecutionPlan(config, self.base_dir, sysinfo)

                # Format confirmation summary
                summary_lines = [
                    f"Target Distribution:  {config.distro_name} ({config.distro})",
                    f"Desktop Environment:  {config.desktop_environment.upper()}",
                    f"Total Planned Steps:  {len(plan.steps)}",
                    "",
                    "Active Modules to Execute:"
                ]
                for s in plan.steps[:6]:
                    summary_lines.append(f" • {s.title}")
                if len(plan.steps) > 6:
                    summary_lines.append(f" • ... and {len(plan.steps) - 6} additional steps")

                summary_lines.extend([
                    "",
                    "Would you like to start the post-installation process?"
                ])

                confirm = ConfirmScreen(
                    stdscr,
                    "Confirm Post-Installation Setup",
                    "\n".join(summary_lines)
                ).run()

                if confirm:
                    # Run execution screen
                    exec_screen = ExecutionScreen(stdscr, plan, dry_run=self.dry_run)
                    success = exec_screen.run()

                    # Final finish alert
                    status_title = "Installation Complete!" if success else "Installation Completed with Warnings"
                    msg = (
                        "Post-installation configuration has finished successfully!\n\n"
                        "Please restart your session or reboot your system\n"
                        "for all user permissions, group memberships, and\n"
                        "system services to take full effect."
                    )
                    ConfirmScreen(stdscr, status_title, msg, is_alert=True).run()
                    return 0 if success else 1


def run_tui(
    base_dir: Optional[Path] = None,
    config_path: Optional[str] = None,
    dry_run: bool = False,
    distro_override: Optional[str] = None
) -> int:
    """Wrapper function to safely launch the TUI with terminal cleanup."""
    app = PostInstallTUI(base_dir, config_path, dry_run, distro_override)
    try:
        return curses.wrapper(app.start)
    except KeyboardInterrupt:
        return 130
