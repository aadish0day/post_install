#!/usr/bin/env python3
"""
Color palette and curses attribute management for the Archinstall-style TUI.
"""

from __future__ import annotations

import curses


class Colors:
    NORMAL = 1
    PRIMARY = 2      # Cyan / Arch Blue
    HIGHLIGHT = 3    # White on Blue
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
        if not curses.has_colors():
            return
        curses.start_color()
        curses.use_default_colors()
        pairs = [
            (cls.NORMAL, -1, -1),
            (cls.PRIMARY, curses.COLOR_CYAN, -1),
            (cls.HIGHLIGHT, curses.COLOR_WHITE, curses.COLOR_BLUE),
            (cls.SUCCESS, curses.COLOR_GREEN, -1),
            (cls.WARNING, curses.COLOR_YELLOW, -1),
            (cls.ERROR, curses.COLOR_RED, -1),
            (cls.DIM, curses.COLOR_WHITE, -1),
            (cls.ACCENT, curses.COLOR_MAGENTA, -1),
            (cls.HEADER, curses.COLOR_CYAN, -1),
            (cls.FOOTER, curses.COLOR_BLACK, curses.COLOR_CYAN),
            (cls.BORDER, curses.COLOR_CYAN, -1),
            (cls.TAG, curses.COLOR_CYAN, -1),
        ]
        for pair_id, fg, bg in pairs:
            try:
                curses.init_pair(pair_id, fg, bg)
            except Exception:
                pass

    @classmethod
    def get(cls, pair_id: int, bold: bool = False, dim: bool = False) -> int:
        attr = curses.color_pair(pair_id)
        if bold:
            attr |= curses.A_BOLD
        if dim:
            attr |= curses.A_DIM
        return attr

    @classmethod
    def normal(cls) -> int: return cls.get(cls.NORMAL)
    @classmethod
    def primary(cls, bold: bool = True) -> int: return cls.get(cls.PRIMARY, bold=bold)
    @classmethod
    def highlight(cls, bold: bool = True) -> int: return cls.get(cls.HIGHLIGHT, bold=bold)
    @classmethod
    def success(cls, bold: bool = True) -> int: return cls.get(cls.SUCCESS, bold=bold)
    @classmethod
    def warning(cls, bold: bool = True) -> int: return cls.get(cls.WARNING, bold=bold)
    @classmethod
    def error(cls, bold: bool = True) -> int: return cls.get(cls.ERROR, bold=bold)
    @classmethod
    def dim(cls) -> int: return cls.get(cls.DIM, dim=True)
    @classmethod
    def accent(cls, bold: bool = True) -> int: return cls.get(cls.ACCENT, bold=bold)
    @classmethod
    def header(cls) -> int: return cls.get(cls.HEADER, bold=True)
    @classmethod
    def footer(cls) -> int: return cls.get(cls.FOOTER, bold=True)
    @classmethod
    def border(cls) -> int: return cls.get(cls.BORDER)

