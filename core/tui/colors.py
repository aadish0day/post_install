#!/usr/bin/env python3
"""
Color palette and curses attribute management for the Archinstall-style TUI.
"""

from __future__ import annotations

import curses
from typing import Dict


class Colors:
    # Color Pair IDs
    NORMAL = 1
    PRIMARY = 2      # Cyan / Arch Blue
    HIGHLIGHT = 3    # White on Blue (Selected item)
    SUCCESS = 4      # Green
    WARNING = 5      # Yellow / Gold
    ERROR = 6        # Red
    DIM = 7          # Dim / Gray
    ACCENT = 8       # Magenta
    HEADER = 9       # White on Dark Cyan/Blue
    FOOTER = 10      # Black on Cyan/White
    BORDER = 11      # Dark Cyan/Gray
    TAG = 12         # Blue/Cyan tag

    @classmethod
    def init(cls) -> None:
        """Initialize color pairs with safe curses fallback."""
        if not curses.has_colors():
            return

        curses.start_color()
        curses.use_default_colors()

        try:
            # Standard color pairs
            curses.init_pair(cls.NORMAL, -1, -1)
            curses.init_pair(cls.PRIMARY, curses.COLOR_CYAN, -1)
            curses.init_pair(cls.HIGHLIGHT, curses.COLOR_WHITE, curses.COLOR_BLUE)
            curses.init_pair(cls.SUCCESS, curses.COLOR_GREEN, -1)
            curses.init_pair(cls.WARNING, curses.COLOR_YELLOW, -1)
            curses.init_pair(cls.ERROR, curses.COLOR_RED, -1)
            curses.init_pair(cls.DIM, curses.COLOR_WHITE, -1)
            curses.init_pair(cls.ACCENT, curses.COLOR_MAGENTA, -1)
            curses.init_pair(cls.HEADER, curses.COLOR_CYAN, -1)
            curses.init_pair(cls.FOOTER, curses.COLOR_BLACK, curses.COLOR_CYAN)
            curses.init_pair(cls.BORDER, curses.COLOR_CYAN, -1)
            curses.init_pair(cls.TAG, curses.COLOR_CYAN, -1)
        except Exception:
            pass

    @classmethod
    def normal(cls) -> int:
        return curses.color_pair(cls.NORMAL)

    @classmethod
    def primary(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.PRIMARY)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def highlight(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.HIGHLIGHT)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def success(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.SUCCESS)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def warning(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.WARNING)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def error(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.ERROR)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def dim(cls) -> int:
        return curses.color_pair(cls.DIM) | curses.A_DIM

    @classmethod
    def accent(cls, bold: bool = True) -> int:
        attr = curses.color_pair(cls.ACCENT)
        return attr | curses.A_BOLD if bold else attr

    @classmethod
    def header(cls) -> int:
        return curses.color_pair(cls.HEADER) | curses.A_BOLD

    @classmethod
    def footer(cls) -> int:
        return curses.color_pair(cls.FOOTER) | curses.A_BOLD

    @classmethod
    def border(cls) -> int:
        return curses.color_pair(cls.BORDER)
