#!/usr/bin/env python3
"""
Drawing widgets and box rendering utilities for the Archinstall-style TUI.
"""

from __future__ import annotations

import curses
from typing import Optional

from core.tui.colors import Colors


def draw_header(stdscr: curses.window, title: str, subtitle: Optional[str] = None) -> None:
    """Draw the top Archinstall header banner."""
    max_y, max_x = stdscr.getmaxyx()
    if max_y < 3 or max_x < 20:
        return

    # Banner text
    title_str = f" {title} "
    stdscr.attron(Colors.header())
    stdscr.addstr(0, max(0, (max_x - len(title_str)) // 2), title_str[:max_x - 1])
    stdscr.attroff(Colors.header())

    if subtitle and max_y > 4:
        sub_str = f" {subtitle} "
        stdscr.attron(Colors.dim())
        stdscr.addstr(1, max(0, (max_x - len(sub_str)) // 2), sub_str[:max_x - 1])
        stdscr.attroff(Colors.dim())

    # Divider line
    div_y = 2 if subtitle and max_y > 4 else 1
    stdscr.attron(Colors.dim())
    stdscr.addstr(div_y, 0, "─" * (max_x - 1))
    stdscr.attroff(Colors.dim())


def draw_footer(stdscr: curses.window, keybinds: str) -> None:
    """Draw the bottom keybindings status bar."""
    max_y, max_x = stdscr.getmaxyx()
    if max_y < 4 or max_x < 20:
        return

    y = max_y - 1
    # Fill background
    stdscr.attron(Colors.footer())
    stdscr.addstr(y, 0, " " * (max_x - 1))
    stdscr.addstr(y, 1, keybinds[:max_x - 2])
    stdscr.attroff(Colors.footer())


def draw_box(
    stdscr: curses.window,
    y: int,
    x: int,
    h: int,
    w: int,
    title: Optional[str] = None,
    color_attr: Optional[int] = None,
    fill: bool = False
) -> None:
    """Draw a clean unicode box with optional title."""
    max_y, max_x = stdscr.getmaxyx()
    if y >= max_y or x >= max_x or h <= 1 or w <= 1:
        return

    # Bound coordinates
    actual_h = min(h, max_y - y)
    actual_w = min(w, max_x - x)
    if actual_h < 2 or actual_w < 2:
        return

    attr = color_attr if color_attr is not None else Colors.border()

    # Fill background if requested
    if fill:
        for row in range(y, y + actual_h):
            try:
                stdscr.addstr(row, x, " " * (actual_w - 1))
            except curses.error:
                pass

    try:
        # Top border
        top = "┌" + "─" * (actual_w - 2) + "┐"
        stdscr.addstr(y, x, top[:max_x - x - 1], attr)

        # Title on border
        if title:
            t_str = f" {title} "
            if len(t_str) < actual_w - 4:
                stdscr.addstr(y, x + 2, t_str, Colors.primary(bold=True))

        # Side borders
        for row in range(y + 1, y + actual_h - 1):
            stdscr.addstr(row, x, "│", attr)
            stdscr.addstr(row, x + actual_w - 1, "│", attr)

        # Bottom border
        bot = "└" + "─" * (actual_w - 2) + "┘"
        stdscr.addstr(y + actual_h - 1, x, bot[:max_x - x - 1], attr)
    except curses.error:
        pass


def safe_addstr(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    """Write text to window without throwing curses error at bottom-right edge."""
    max_y, max_x = stdscr.getmaxyx()
    if y < 0 or y >= max_y or x < 0 or x >= max_x:
        return
    max_len = max_x - x - 1
    if max_len <= 0:
        return
    try:
        stdscr.addstr(y, x, text[:max_len], attr)
    except curses.error:
        pass
