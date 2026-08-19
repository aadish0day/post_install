"""
Archinstall-style TUI components.
"""

from core.tui.app import PostInstallTUI, run_tui
from core.tui.screens import GlobalMenuScreen, OptionListScreen, SelectListScreen, InputScreen, ConfirmScreen, ExecutionScreen
from core.tui.colors import Colors

__all__ = [
    "PostInstallTUI",
    "run_tui",
    "GlobalMenuScreen",
    "OptionListScreen",
    "SelectListScreen",
    "InputScreen",
    "ConfirmScreen",
    "ExecutionScreen",
    "Colors"
]
