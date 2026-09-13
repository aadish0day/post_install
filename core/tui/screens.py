#!/usr/bin/env python3
"""
Interactive Screen implementations for the Archinstall-style TUI.
Provides GlobalMenuScreen, OptionListScreen, SelectListScreen, InputScreen, ConfirmScreen, and ExecutionScreen
with full Vim keybindings navigation (h/j/k/l, g/G, Ctrl+d/u, Space/x).
"""

from __future__ import annotations

import asyncio
import curses
import queue
import threading
import time
from typing import Dict, List, Optional, Tuple

from core.config import PostInstallConfig
from core.detector import SystemInfo
from core.runner import ExecutionEvent, ExecutionPlan, StepStatus, run_plan
from core.tui.model import (
    EXIT_MESSAGE,
    EXIT_TITLE,
    MenuState,
    build_menu_items,
    handle_item_select,
    is_progress_line,
    load_config,
    quick_toggle,
    save_config,
)
from core.tui.colors import Colors
from core.tui.widgets import draw_box, draw_footer, draw_header, safe_addstr


class CursesPrompter:
    """Prompter implementation backed by the curses dialog screens."""

    def __init__(self, stdscr: curses.window):
        self.stdscr = stdscr

    async def select_one(self, title: str, options: List[Tuple[str, str]], current: Optional[str]) -> Optional[str]:
        return OptionListScreen(self.stdscr, title, options, current or "").run()

    async def select_many(self, title: str, options: List[Tuple[str, str, bool]]) -> Optional[List[str]]:
        return SelectListScreen(self.stdscr, title, options).run()

    async def ask_text(self, title: str, prompt: str, default: str = "") -> Optional[str]:
        return InputScreen(self.stdscr, title, prompt, default).run()

    async def confirm(self, title: str, message: str) -> bool:
        return ConfirmScreen(self.stdscr, title, message).run()

    async def notify(self, title: str, message: str) -> None:
        ConfirmScreen(self.stdscr, title, message, is_alert=True).run()


class GlobalMenuScreen:
    """The central Archinstall-style configuration menu screen."""

    def __init__(self, stdscr: curses.window, state: MenuState):
        self.stdscr = stdscr
        self.state = state
        self.ui = CursesPrompter(stdscr)
        self.cursor_idx = 0
        self.scroll_offset = 0

    @property
    def config(self) -> PostInstallConfig:
        return self.state.config

    @property
    def sysinfo(self) -> SystemInfo:
        return self.state.sysinfo

    def run(self) -> Optional[str]:
        """Main event loop for the Global Menu with full Vim keybinding support."""
        curses.curs_set(0)
        self.stdscr.keypad(True)
        self.stdscr.nodelay(False)

        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()

            if max_y < 16 or max_x < 60:
                safe_addstr(self.stdscr, 1, 1, "Terminal window is too small.", Colors.warning())
                safe_addstr(self.stdscr, 2, 1, f"Please resize to at least 80x24 (Current: {max_x}x{max_y}).", Colors.dim())
                safe_addstr(self.stdscr, 4, 1, "Press 'q' to exit.", Colors.normal())
                self.stdscr.refresh()
                ch = self.stdscr.getch()
                if ch in (ord('q'), ord('Q'), 27):
                    return "exit"
                continue

            items = build_menu_items(self.state)
            total_items = len(items)
            self.cursor_idx = max(0, min(self.cursor_idx, total_items - 1))

            # Header
            sub_info = f"Host: {self.sysinfo.hostname} ({self.sysinfo.cpu_vendor.upper()}) | OS Folder: ./{self.config.distro}/ | User: {self.sysinfo.username}"
            draw_header(self.stdscr, f"{self.config.distro_name.upper()} POST-INSTALLATION SUITE", sub_info)

            # Footer with Vim keybindings indicator
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [g/G] Top/Bottom  [Ctrl+d/u] Scroll  [Enter/l] Open  [Space/x] Toggle  [s] Save  [o] Load  [Esc/q] Exit ")

            # Calculate box dimensions
            content_top = 3
            content_bottom = max_y - 2
            available_h = content_bottom - content_top + 1

            split_mode = max_x >= 90
            if split_mode:
                menu_w = int(max_x * 0.54)
                preview_w = max_x - menu_w - 2
                menu_x = 1
                preview_x = menu_w + 2
                menu_h = available_h
                preview_h = available_h
            else:
                menu_w = max_x - 2
                preview_w = max_x - 2
                menu_x = 1
                preview_x = 1
                menu_h = max(8, int(available_h * 0.6))
                preview_h = available_h - menu_h

            # Draw Menu Box
            draw_box(self.stdscr, content_top, menu_x, menu_h, menu_w, f"Configuration Menu [{self.config.distro.upper()}]", Colors.primary(bold=True))

            # Adjust scroll
            visible_rows = menu_h - 2
            if self.cursor_idx < self.scroll_offset:
                self.scroll_offset = self.cursor_idx
            elif self.cursor_idx >= self.scroll_offset + visible_rows:
                self.scroll_offset = self.cursor_idx - visible_rows + 1

            # Render menu items
            for i in range(visible_rows):
                item_idx = self.scroll_offset + i
                if item_idx >= total_items:
                    break

                item = items[item_idx]
                row_y = content_top + 1 + i
                is_selected = (item_idx == self.cursor_idx)

                prefix = " > " if is_selected else "   "
                lbl = item.label
                val = item.value_display

                avail_txt_w = menu_w - 4
                lbl_len = len(lbl)
                val_len = len(val)

                if is_selected:
                    # Highlight active row in bold white on blue
                    if lbl_len + val_len + 4 <= avail_txt_w:
                        spaces = " " * (avail_txt_w - lbl_len - val_len - 3)
                        full_line = f"{prefix}{lbl}{spaces}{val}"
                    else:
                        truncated_lbl = lbl[:max(8, avail_txt_w - val_len - 6)] + ".."
                        spaces = " " * max(1, avail_txt_w - len(truncated_lbl) - val_len - 3)
                        full_line = f"{prefix}{truncated_lbl}{spaces}{val}"
                    safe_addstr(self.stdscr, row_y, menu_x + 1, full_line.ljust(menu_w - 2), Colors.highlight(bold=True))
                else:
                    # Clear row background
                    safe_addstr(self.stdscr, row_y, menu_x + 1, " " * (menu_w - 2), Colors.normal())

                    # Draw label on the left
                    lbl_attr = Colors.accent(bold=True) if item.is_action else Colors.normal()
                    max_lbl_w = max(10, avail_txt_w - val_len - 4)
                    display_lbl = lbl if len(lbl) <= max_lbl_w else lbl[:max_lbl_w - 2] + ".."
                    safe_addstr(self.stdscr, row_y, menu_x + 1, f"{prefix}{display_lbl}", lbl_attr)

                    # Determine color for the value tag on the right
                    if val == "[Yes]":
                        val_attr = Colors.success(bold=True)
                    elif val == "[No]":
                        val_attr = Colors.error(bold=True)
                    elif val.startswith("[") and val.endswith("]"):
                        val_attr = Colors.primary(bold=True)
                    else:
                        val_attr = Colors.normal()

                    val_x = menu_x + menu_w - 1 - val_len - 1
                    safe_addstr(self.stdscr, row_y, val_x, val, val_attr)

            # Draw Preview Box
            selected_item = items[self.cursor_idx]
            prev_y = content_top if split_mode else content_top + menu_h
            draw_box(self.stdscr, prev_y, preview_x, preview_h, preview_w, "Item Details & Preview", Colors.primary(bold=True))

            safe_addstr(self.stdscr, prev_y + 1, preview_x + 2, f"Option: {selected_item.label}", Colors.primary(bold=True))
            safe_addstr(self.stdscr, prev_y + 2, preview_x + 2, selected_item.description, Colors.dim())
            safe_addstr(self.stdscr, prev_y + 3, preview_x + 2, "─" * (preview_w - 4), Colors.dim())

            prev_visible_rows = preview_h - 5
            for p_i, line in enumerate(selected_item.preview_lines[:prev_visible_rows]):
                p_attr = Colors.normal()
                if "[Yes]" in line or line.startswith("Status: Yes"):
                    p_attr = Colors.success(bold=True)
                elif "[No]" in line or line.startswith("Status: No"):
                    p_attr = Colors.error(bold=True)
                elif line.startswith("==") or line.startswith("Active") or line.startswith("Modular") or line.startswith("Available"):
                    p_attr = Colors.accent(bold=True)
                elif line.startswith(" •"):
                    p_attr = Colors.primary(bold=False)
                safe_addstr(self.stdscr, prev_y + 4 + p_i, preview_x + 2, line, p_attr)

            self.stdscr.refresh()

            # Handle Keys (with Full Vim Keybindings)
            key = self.stdscr.getch()

            # Toggle Boolean / Quick Checkmark: Space or x
            if key in (ord(' '), ord('x'), ord('X')):
                quick_toggle(self.state, selected_item.key)

            # Select / Open Submenu: Enter or l (Vim forward) or Right Arrow
            elif key in (10, 13, curses.KEY_ENTER, ord('l'), curses.KEY_RIGHT):
                action_res = asyncio.run(handle_item_select(self.state, selected_item, self.ui))
                if action_res in ("install", "exit"):
                    return action_res

            # Save Config: s / S
            elif key in (ord('s'), ord('S')):
                asyncio.run(save_config(self.state, self.ui))

            # Load Config: o / O
            elif key in (ord('o'), ord('O')):
                asyncio.run(load_config(self.state, self.ui))

            # Exit / Back: Esc / q / Q
            elif key in (ord('q'), ord('Q'), 27):
                confirm = ConfirmScreen(self.stdscr, EXIT_TITLE, EXIT_MESSAGE).run()
                if confirm:
                    return "exit"

            else:
                self.cursor_idx = _handle_nav(key, self.cursor_idx, total_items, max(1, visible_rows // 2))


def _handle_nav(key: int, idx: int, total: int, step: int = 3) -> int:
    if total <= 0:
        return 0
    if key in (curses.KEY_DOWN, ord('j'), ord('J')):
        return (idx + 1) % total
    if key in (curses.KEY_UP, ord('k'), ord('K')):
        return (idx - 1) % total
    if key in (curses.KEY_HOME, ord('g')):
        return 0
    if key in (curses.KEY_END, ord('G')):
        return total - 1
    if key in (4, 6, curses.KEY_NPAGE):
        return min(total - 1, idx + step)
    if key in (21, 2, curses.KEY_PPAGE):
        return max(0, idx - step)
    return idx


class OptionListScreen:
    """Single-selection radio screen with Vim navigation (j/k, g/G, l/Enter)."""

    def __init__(self, stdscr: curses.window, title: str, options: List[Tuple[str, str]], current_val: str):
        self.stdscr = stdscr
        self.title = title
        self.options = options
        self.current_val = current_val
        self.cursor_idx = next((i for i, (k, _) in enumerate(options) if k == current_val), 0)

    def run(self) -> Optional[str]:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [g/G] Top/Bottom  [Enter/l/Space] Select  [Esc/h/q] Cancel ")

            box_h = min(max_y - 6, len(self.options) + 4)
            box_w = min(max_x - 4, 80)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))

            for i, (k, label) in enumerate(self.options):
                is_selected = (i == self.cursor_idx)
                radio = "(*)" if k == self.current_val else "( )"
                line = f" {radio} {label}"
                attr = Colors.highlight(bold=True) if is_selected else Colors.normal()
                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 2, line.ljust(box_w - 4), attr)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (10, 13, curses.KEY_ENTER, ord('l'), ord(' ')):
                return self.options[self.cursor_idx][0]
            if key in (ord('q'), ord('Q'), ord('h'), 27):
                return None
            self.cursor_idx = _handle_nav(key, self.cursor_idx, len(self.options))


class SelectListScreen:
    """Multi-selection checklist screen with Vim navigation and toggles."""

    def __init__(self, stdscr: curses.window, title: str, options: List[Tuple[str, str, bool]]):
        self.stdscr = stdscr
        self.title = title
        self.options = options
        self.selected: Dict[str, bool] = {k: state for k, _, state in options}
        self.cursor_idx = 0

    def run(self) -> Optional[List[str]]:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [j/k or ↑/↓] Move  [Space/x] Toggle  [a] All  [c] Clear  [g/G] Top/Bottom  [Enter] Confirm  [Esc/h/q] Cancel ")

            box_h = min(max_y - 6, len(self.options) + 4)
            box_w = min(max_x - 4, 88)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))

            for i, (k, label, _) in enumerate(self.options):
                is_selected = (i == self.cursor_idx)
                is_checked = self.selected.get(k, False)
                check = "[✓]" if is_checked else "[ ]"
                line = f" {check} {label}"

                if is_selected:
                    attr = Colors.highlight(bold=True)
                else:
                    attr = Colors.success(bold=True) if is_checked else Colors.normal()

                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 2, line.ljust(box_w - 4), attr)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (ord(' '), ord('x'), ord('X')):
                cur_k = self.options[self.cursor_idx][0]
                self.selected[cur_k] = not self.selected.get(cur_k, False)
            elif key in (ord('a'), ord('A')):
                for k, _, _ in self.options:
                    self.selected[k] = True
            elif key in (ord('c'), ord('C')):
                for k, _, _ in self.options:
                    self.selected[k] = False
            elif key in (10, 13, curses.KEY_ENTER):
                return [k for k, _, _ in self.options if self.selected.get(k, False)]
            elif key in (27, ord('q'), ord('Q'), ord('h')):
                return None
            else:
                self.cursor_idx = _handle_nav(key, self.cursor_idx, len(self.options))


class InputScreen:
    """Text entry dialog box."""

    def __init__(self, stdscr: curses.window, title: str, prompt: str, default_val: str = ""):
        self.stdscr = stdscr
        self.title = title
        self.prompt = prompt
        self.buffer = list(default_val)
        self.cursor_pos = len(self.buffer)

    def run(self) -> Optional[str]:
        curses.curs_set(1)
        self.stdscr.nodelay(False)
        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [Enter] Submit  [Esc] Cancel ")

            box_h = 8
            box_w = min(max_x - 4, 70)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, Colors.primary(bold=True))
            safe_addstr(self.stdscr, box_y + 2, box_x + 3, self.prompt, Colors.normal())

            field_w = box_w - 6
            field_y = box_y + 4
            field_x = box_x + 3
            input_text = "".join(self.buffer)
            safe_addstr(self.stdscr, field_y, field_x, input_text.ljust(field_w), Colors.highlight())

            cur_screen_x = field_x + self.cursor_pos
            try:
                self.stdscr.move(field_y, min(cur_screen_x, field_x + field_w - 1))
            except curses.error:
                pass

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (10, 13, curses.KEY_ENTER):
                curses.curs_set(0)
                return "".join(self.buffer).strip()
            elif key == 27:
                curses.curs_set(0)
                return None
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if self.cursor_pos > 0:
                    self.buffer.pop(self.cursor_pos - 1)
                    self.cursor_pos -= 1
            elif key == curses.KEY_DC:
                if self.cursor_pos < len(self.buffer):
                    self.buffer.pop(self.cursor_pos)
            elif key == curses.KEY_LEFT:
                self.cursor_pos = max(0, self.cursor_pos - 1)
            elif key == curses.KEY_RIGHT:
                self.cursor_pos = min(len(self.buffer), self.cursor_pos + 1)
            elif key >= 32 and key <= 126:
                if len(self.buffer) < field_w - 2:
                    self.buffer.insert(self.cursor_pos, chr(key))
                    self.cursor_pos += 1


class ConfirmScreen:
    """Confirmation modal dialog with Proceed / Cancel buttons and Vim navigation."""

    def __init__(self, stdscr: curses.window, title: str, message: str, is_alert: bool = False):
        self.stdscr = stdscr
        self.title = title
        self.message = message
        self.is_alert = is_alert
        self.btn_idx = 0

    def run(self) -> bool:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        lines = self.message.split("\n")

        while True:
            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()
            draw_header(self.stdscr, self.title)
            draw_footer(self.stdscr, " [h/l or ←/→] Switch Button  [Enter/y] Confirm  [Esc/n/q] Cancel ")

            box_h = min(max_y - 4, len(lines) + 6)
            box_w = min(max_x - 4, 76)
            box_y = max(3, (max_y - box_h) // 2)
            box_x = max(2, (max_x - box_w) // 2)

            color = Colors.warning(bold=True) if not self.is_alert else Colors.primary(bold=True)
            draw_box(self.stdscr, box_y, box_x, box_h, box_w, self.title, color)

            for i, line in enumerate(lines):
                safe_addstr(self.stdscr, box_y + 2 + i, box_x + 3, line, Colors.normal())

            btn_y = box_y + box_h - 2
            if self.is_alert:
                btn_str = "[  OK (Enter)  ]"
                safe_addstr(self.stdscr, btn_y, box_x + (box_w - len(btn_str)) // 2, btn_str, Colors.highlight(bold=True))
            else:
                btn1 = "[  Proceed (Enter)  ]"
                btn2 = "[  Cancel (Esc)  ]"
                spacing = (box_w - len(btn1) - len(btn2) - 6) // 2
                x1 = box_x + 4
                x2 = x1 + len(btn1) + spacing

                attr1 = Colors.highlight(bold=True) if self.btn_idx == 0 else Colors.normal()
                attr2 = Colors.highlight(bold=True) if self.btn_idx == 1 else Colors.normal()

                safe_addstr(self.stdscr, btn_y, x1, btn1, attr1)
                safe_addstr(self.stdscr, btn_y, x2, btn2, attr2)

            self.stdscr.refresh()
            key = self.stdscr.getch()

            if key in (10, 13, curses.KEY_ENTER):
                return (self.btn_idx == 0)
            elif key in (27, ord('q'), ord('Q'), ord('n'), ord('N')):
                return False
            # Vim navigation for buttons: h (left), l (right), j/k/Tab (toggle)
            elif key in (curses.KEY_LEFT, ord('h'), ord('H')):
                if not self.is_alert:
                    self.btn_idx = 0
            elif key in (curses.KEY_RIGHT, ord('l'), ord('L')):
                if not self.is_alert:
                    self.btn_idx = 1
            elif key in (curses.KEY_DOWN, curses.KEY_UP, ord('j'), ord('k'), 9):  # Tab
                if not self.is_alert:
                    self.btn_idx = 1 - self.btn_idx
            elif key in (ord('y'), ord('Y')):
                return True


class ExecutionScreen:
    """Live step-by-step progress monitor with spinner and scrolling log view."""

    def __init__(self, stdscr: curses.window, plan: ExecutionPlan, dry_run: bool = False):
        self.stdscr = stdscr
        self.plan = plan
        self.dry_run = dry_run
        self.log_lines: List[str] = []
        self.spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.spinner_idx = 0
        self.current_step_idx = 0
        self.plan_completed = False
        self.has_errors = False
        self.log_scroll_offset = 0
        self.auto_scroll = True
        self.event_queue: queue.Queue[ExecutionEvent] = queue.Queue()

    def _worker(self) -> None:
        try:
            for event in run_plan(self.plan, dry_run=self.dry_run):
                self.event_queue.put(event)
        except Exception as e:
            err_step = self.plan.steps[min(self.current_step_idx, len(self.plan.steps) - 1)]
            self.event_queue.put(ExecutionEvent(event_type="output", step_index=self.current_step_idx, step=err_step, message=f"Runner Error: {e}"))
            self.event_queue.put(ExecutionEvent(event_type="plan_complete", step_index=len(self.plan.steps) - 1, step=err_step, message="Completed with errors."))

    def run(self) -> bool:
        curses.curs_set(0)
        self.stdscr.nodelay(True)

        worker_thread = threading.Thread(target=self._worker, daemon=True)
        worker_thread.start()

        while True:
            # Drain event queue
            while True:
                try:
                    event = self.event_queue.get_nowait()
                    self.current_step_idx = event.step_index
                    if event.event_type == "output":
                        # Collapse consecutive download progress lines into one
                        is_prog = event.is_transient or is_progress_line(event.message)
                        if (is_prog
                                and self.log_lines
                                and (is_progress_line(self.log_lines[-1]) or getattr(self, "_last_was_transient", False))):
                            self.log_lines[-1] = event.message
                        else:
                            self.log_lines.append(event.message)
                        self._last_was_transient = is_prog
                    elif event.event_type == "step_start":
                        self.log_lines.append(f"==> {event.step.title}")
                    elif event.event_type == "step_complete":
                        self.log_lines.append(f"✓ Completed: {event.step.title} ({event.step.duration:.1f}s)")
                    elif event.event_type == "step_fail":
                        self.has_errors = True
                        self.log_lines.append(f"✗ ERROR: {event.step.title}")
                    elif event.event_type == "plan_complete":
                        self.plan_completed = True
                except queue.Empty:
                    break

            if not worker_thread.is_alive() and self.event_queue.empty():
                self.plan_completed = True

            self.spinner_idx = (self.spinner_idx + 1) % len(self.spinner_frames)

            self.stdscr.erase()
            max_y, max_x = self.stdscr.getmaxyx()

            status_txt = "DRY-RUN EXECUTION" if self.dry_run else "EXECUTING POST-INSTALLATION STEPS"
            sub_title = f"Step {min(len(self.plan.steps), self.current_step_idx + 1)} of {len(self.plan.steps)}"
            draw_header(self.stdscr, status_txt, sub_title)

            if not self.plan_completed:
                draw_footer(self.stdscr, " [j/k or ↑/↓] Scroll Logs  [G] Auto-scroll  Please wait while installing... ")
            else:
                draw_footer(self.stdscr, " [j/k or ↑/↓] Scroll Logs  Installation Finished! Press [Enter] or [q] to exit ")

            content_top = 3
            content_bottom = max_y - 2
            available_h = content_bottom - content_top + 1

            steps_h = min(12, max(6, int(available_h * 0.38)))
            log_h = available_h - steps_h - 1

            # Draw Steps Box
            draw_box(self.stdscr, content_top, 1, steps_h, max_x - 2, f"Execution Plan [./{self.plan.config.distro}/]", Colors.primary(bold=True))

            visible_steps = steps_h - 2
            step_offset = max(0, self.current_step_idx - visible_steps + 1)

            for i in range(visible_steps):
                s_idx = step_offset + i
                if s_idx >= len(self.plan.steps):
                    break
                step = self.plan.steps[s_idx]
                row_y = content_top + 1 + i

                if step.status == StepStatus.COMPLETED:
                    icon = "[✓]"
                    attr = Colors.success(bold=True)
                elif step.status == StepStatus.RUNNING:
                    icon = f"[{self.spinner_frames[self.spinner_idx]}]"
                    attr = Colors.warning(bold=True)
                elif step.status == StepStatus.FAILED:
                    icon = "[✗]"
                    attr = Colors.error(bold=True)
                else:
                    icon = "[·]"
                    attr = Colors.dim()

                step_line = f" {icon} {s_idx + 1}. {step.title}"
                safe_addstr(self.stdscr, row_y, 3, step_line, attr)

            # Draw Logs Box
            log_y = content_top + steps_h
            draw_box(self.stdscr, log_y, 1, log_h, max_x - 2, "Live Command Output & Logs", Colors.primary(bold=True))

            visible_logs = log_h - 2
            total_logs = len(self.log_lines)

            if self.auto_scroll:
                start_log_idx = max(0, total_logs - visible_logs)
            else:
                start_log_idx = max(0, min(self.log_scroll_offset, max(0, total_logs - visible_logs)))

            rendered_logs = self.log_lines[start_log_idx:start_log_idx + visible_logs]
            for l_i, l_text in enumerate(rendered_logs):
                l_attr = Colors.normal()
                if l_text.startswith("✓"):
                    l_attr = Colors.success(bold=True)
                elif l_text.startswith("✗") or "ERROR" in l_text:
                    l_attr = Colors.error(bold=True)
                elif l_text.startswith("==>") or l_text.startswith("[EXEC]"):
                    l_attr = Colors.accent(bold=True)
                elif l_text.startswith("[DRY-RUN]"):
                    l_attr = Colors.warning()
                safe_addstr(self.stdscr, log_y + 1 + l_i, 3, l_text[:max_x - 6], l_attr)

            self.stdscr.refresh()

            # Handle interactive scrolling & exit
            key = self.stdscr.getch()
            if key != -1:
                if key in (curses.KEY_UP, ord('k'), ord('K')):
                    self.auto_scroll = False
                    self.log_scroll_offset = max(0, (start_log_idx if self.auto_scroll else self.log_scroll_offset) - 1)
                elif key in (curses.KEY_DOWN, ord('j'), ord('J')):
                    self.log_scroll_offset = min(max(0, total_logs - visible_logs), (start_log_idx if self.auto_scroll else self.log_scroll_offset) + 1)
                    if self.log_scroll_offset >= total_logs - visible_logs:
                        self.auto_scroll = True
                elif key in (4, 6, curses.KEY_NPAGE):  # Ctrl+d / PageDown
                    self.log_scroll_offset = min(max(0, total_logs - visible_logs), (start_log_idx if self.auto_scroll else self.log_scroll_offset) + 5)
                    if self.log_scroll_offset >= total_logs - visible_logs:
                        self.auto_scroll = True
                elif key in (21, 2, curses.KEY_PPAGE):  # Ctrl+u / PageUp
                    self.auto_scroll = False
                    self.log_scroll_offset = max(0, (start_log_idx if self.auto_scroll else self.log_scroll_offset) - 5)
                elif key in (curses.KEY_HOME, ord('g')):
                    self.auto_scroll = False
                    self.log_scroll_offset = 0
                elif key in (curses.KEY_END, ord('G')):
                    self.auto_scroll = True
                elif self.plan_completed and key in (10, 13, curses.KEY_ENTER, ord('q'), ord('Q'), 27):
                    self.stdscr.nodelay(False)
                    return not self.has_errors

            time.sleep(0.033)  # Smooth 30 FPS rendering loop
