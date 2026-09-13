#!/usr/bin/env python3
"""
Main TUI Application controller for the post-installation suite.
Launches the Textual (archinstall-style) interface when Textual is installed,
otherwise falls back to the built-in curses interface.
"""

from __future__ import annotations

import curses
import importlib.metadata
import importlib.util
import os
from pathlib import Path
from typing import Optional

from core.config import PostInstallConfig
from core.detector import detect_system
from core.runner import ExecutionPlan
from core.tui.colors import Colors
from core.tui.model import FINISH_MESSAGE, MenuState, install_summary
from core.tui.screens import ConfirmScreen, ExecutionScreen, GlobalMenuScreen


def load_initial_state(base_dir: Path, config_path: Optional[str], distro_override: Optional[str]) -> MenuState:
    """Detect the system and build the starting configuration for either front-end."""
    sysinfo = detect_system()

    if config_path and os.path.isfile(config_path):
        config = PostInstallConfig.load_json(config_path)
    else:
        config = PostInstallConfig.default_for_system(sysinfo)

    if distro_override:
        config.set_distro(distro_override)

    return MenuState(config=config, sysinfo=sysinfo, base_dir=base_dir)


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

        state = load_initial_state(self.base_dir, self.config_path, self.distro_override)

        # Main Global Menu loop
        while True:
            menu = GlobalMenuScreen(stdscr, state)
            action = menu.run()

            if action == "exit" or action is None:
                return 0

            elif action == "install":
                plan = ExecutionPlan(state.config, self.base_dir, state.sysinfo)

                confirm = ConfirmScreen(
                    stdscr,
                    "Confirm Post-Installation Setup",
                    install_summary(state.config, plan)
                ).run()

                if confirm:
                    exec_screen = ExecutionScreen(stdscr, plan, dry_run=self.dry_run)
                    success = exec_screen.run()

                    status_title = "Installation Complete!" if success else "Installation Completed with Warnings"
                    ConfirmScreen(stdscr, status_title, FINISH_MESSAGE, is_alert=True).run()
                    return 0 if success else 1


TEXTUAL_MIN_MAJOR = 2  # tested with Textual 2.1 and 8.2


def textual_available() -> bool:
    if importlib.util.find_spec("textual") is None:
        return False
    try:
        major = int(importlib.metadata.version("textual").split(".")[0])
    except (importlib.metadata.PackageNotFoundError, ValueError):
        return False
    return major >= TEXTUAL_MIN_MAJOR


def run_tui(
    base_dir: Optional[Path] = None,
    config_path: Optional[str] = None,
    dry_run: bool = False,
    distro_override: Optional[str] = None,
    frontend: str = "auto",
) -> int:
    """Launch the TUI. frontend: "auto" (Textual if installed), "textual", or "curses"."""
    base_dir = base_dir or Path(__file__).resolve().parent.parent.parent

    if frontend == "textual" or (frontend == "auto" and textual_available()):
        from core.tui.textual_app import run_textual_tui
        return run_textual_tui(base_dir, config_path, dry_run, distro_override)

    app = PostInstallTUI(base_dir, config_path, dry_run, distro_override)
    try:
        return curses.wrapper(app.start)
    except KeyboardInterrupt:
        return 130
