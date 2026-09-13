#!/usr/bin/env python3
"""
Textual front-end with the look and feel of archinstall's TUI:
blue title bar, borderless menu with a preview pane on the right,
blue highlighted rows, Yes/No button dialogs and a key-hint footer.

Menu contents and actions come from core.tui.model, shared with the
curses fallback in core.tui.screens.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import ClassVar, Generic, List, Optional, Tuple, TypeVar

from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Center, Horizontal, ScrollableContainer, Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Input, Label, OptionList, RichLog, Rule, SelectionList, Static
from textual.widgets.option_list import Option
from textual.widgets.selection_list import Selection

from core.runner import ExecutionEvent, ExecutionPlan, StepStatus, run_plan
from core.tui.model import (
    FINISH_MESSAGE,
    MenuItem,
    MenuState,
    build_menu_items,
    handle_item_select,
    install_summary,
    is_progress_line,
    load_config,
    quick_toggle,
    save_config,
)

T = TypeVar("T")

APP_CSS = """
Screen {
    color: white;
    background: transparent;
}

* {
    scrollbar-size: 1 1;
    scrollbar-color: white;
    scrollbar-background: black;
}

.app-header {
    dock: top;
    width: 100%;
    height: auto;
    content-align: center middle;
    background: blue;
    color: white;
    text-style: bold;
}

.header-text {
    width: 100%;
    height: auto;
    text-align: center;
    padding: 1 0;
    background: transparent;
}

.content {
    width: 1fr;
    height: 1fr;
    margin: 1 0 0 2;
    background: transparent;
}

.message {
    width: auto;
    height: auto;
    text-align: left;
    padding-bottom: 1;
    background: transparent;
}

.buttons {
    align: center top;
    height: 3;
    background: transparent;
}

.buttons Button {
    width: auto;
    min-width: 8;
    height: 3;
    margin: 0 1;
    border: none;
    background: transparent;
    color: white;
    text-style: none;
}

.buttons Button:focus {
    border: none;
    background: blue;
    color: white;
    text-style: bold;
}

OptionList, SelectionList {
    width: auto;
    height: auto;
    max-height: 1fr;
    min-width: 15%;
    padding-bottom: 3;
    border: none;
    background: transparent;
}

OptionList:focus, SelectionList:focus {
    border: none;
    background: transparent;
}

OptionList > .option-list--option-highlighted,
SelectionList > .option-list--option-highlighted {
    background: blue;
    color: white;
    text-style: bold;
}

Rule.-vertical {
    color: white 40%;
    margin: 0 2;
}

#preview {
    width: 1fr;
    height: 1fr;
    background: transparent;
}

Input {
    height: 3;
    border: solid gray 50%;
    background: transparent;
    color: white;
}

Input:focus {
    border: solid blue;
}

Footer {
    dock: bottom;
    height: 1;
    background: transparent;
    color: white;
}

.footer-key--key {
    background: black;
    color: white;
}

.footer-key--description {
    background: black;
    color: white;
    padding-right: 2;
}
"""


# ----------------------------------------------------------------------------
# Rendering helpers
# ----------------------------------------------------------------------------

def _value_style(value: str) -> str:
    if value == "[Yes]":
        return "bold green"
    if value == "[No]":
        return "bold red"
    return "bold bright_yellow"


def render_preview(item: MenuItem) -> Text:
    text = Text()
    text.append(item.label.strip(), style="bold")
    text.append("\n")
    text.append(item.value_display, style=_value_style(item.value_display))
    text.append("\n\n")
    text.append(item.description, style="italic")
    text.append("\n\n")

    for line in item.preview_lines:
        style = "white"
        if "[Yes]" in line or line.startswith("Status: Yes") or "[Enabled]" in line:
            style = "green"
        elif "[No]" in line or line.startswith("Status: No") or "[Disabled]" in line:
            style = "red"
        elif line.startswith(("==", "Active", "Modular", "Available", "Detected", "Discovered")):
            style = "bold bright_yellow"
        text.append(line + "\n", style=style)
    return text


# ----------------------------------------------------------------------------
# Base screen
# ----------------------------------------------------------------------------

class DialogScreen(Screen[T], Generic[T]):
    """Esc dismisses with None (skip), like archinstall's allow_skip dialogs."""

    BINDINGS: ClassVar = [Binding("escape", "cancel", "Cancel", show=True)]

    def action_cancel(self) -> None:
        self.dismiss(None)


# ----------------------------------------------------------------------------
# Main menu
# ----------------------------------------------------------------------------

class _MenuList(OptionList):
    BINDINGS: ClassVar = [
        Binding("down", "cursor_down", "Down", show=True),
        Binding("up", "cursor_up", "Up", show=True),
        Binding("j", "cursor_down", "Down", show=False),
        Binding("k", "cursor_up", "Up", show=False),
        Binding("g", "first", "First", show=False),
        Binding("G", "last", "Last", show=False),
        Binding("l", "select", "Select", show=False),
    ]


class MainMenuScreen(Screen[Optional[str]]):
    """Global configuration menu. Dismisses with the selected item key."""

    BINDINGS: ClassVar = [
        Binding("space", "toggle", "Toggle", show=True),
        Binding("x", "toggle", "Toggle", show=False),
        Binding("slash", "search", "Search", show=True),
        Binding("s", "save", "Save", show=True),
        Binding("o", "load", "Load", show=True),
        Binding("escape", "close_search", "Close search", show=False),
    ]

    def __init__(self, state: MenuState, focus_key: Optional[str] = None):
        super().__init__()
        self.state = state
        self.focus_key = focus_key
        self.filter = ""
        self.items: List[MenuItem] = []

    def compose(self) -> ComposeResult:
        cfg = self.state.config
        info = self.state.sysinfo
        yield Label(f" {cfg.distro_name} Post-Installation ", classes="app-header")
        with Vertical(classes="content"):
            yield Label(
                f"Host: {info.hostname} ({info.cpu_vendor.upper()})  ·  OS folder: ./{cfg.distro}/  ·  User: {info.username}",
                classes="header-text",
            )
            with Horizontal():
                yield _MenuList(id="menu")
                yield Rule(orientation="vertical")
                with ScrollableContainer(id="preview"):
                    yield Static("", id="preview-content")
        yield Input(placeholder="/filter", id="filter")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#filter", Input).display = False
        self.refresh_items()
        self.query_one("#menu", OptionList).focus()

    def refresh_items(self) -> None:
        menu = self.query_one("#menu", OptionList)
        highlighted = menu.highlighted
        if highlighted is not None and highlighted < menu.option_count:
            self.focus_key = menu.get_option_at_index(highlighted).id

        self.items = build_menu_items(self.state)
        visible = [it for it in self.items if self.filter.lower() in it.label.lower()]

        menu.clear_options()
        menu.add_options([Option(it.label, id=it.key) for it in visible])

        index = next((i for i, it in enumerate(visible) if it.key == self.focus_key), 0)
        if visible:
            menu.highlighted = index
            self._show_preview(visible[index].key)
        else:
            self.query_one("#preview-content", Static).update("")

    def _show_preview(self, key: Optional[str]) -> None:
        item = next((it for it in self.items if it.key == key), None)
        self.query_one("#preview-content", Static).update(render_preview(item) if item else "")

    @on(OptionList.OptionHighlighted, "#menu")
    def _highlighted(self, event: OptionList.OptionHighlighted) -> None:
        self.focus_key = event.option.id
        self._show_preview(event.option.id)

    @on(OptionList.OptionSelected, "#menu")
    def _selected(self, event: OptionList.OptionSelected) -> None:
        self.dismiss(event.option.id)

    def action_toggle(self) -> None:
        if self.focus_key and quick_toggle(self.state, self.focus_key):
            self.refresh_items()

    def action_save(self) -> None:
        self.dismiss("action_save")

    def action_load(self) -> None:
        self.dismiss("action_load")

    def action_search(self) -> None:
        search = self.query_one("#filter", Input)
        search.display = True
        search.focus()

    def action_close_search(self) -> None:
        search = self.query_one("#filter", Input)
        if search.display:
            search.value = ""
            search.display = False
            self.query_one("#menu", OptionList).focus()

    @on(Input.Changed, "#filter")
    def _filter_changed(self, event: Input.Changed) -> None:
        self.filter = event.value
        self.refresh_items()

    @on(Input.Submitted, "#filter")
    def _filter_submitted(self, event: Input.Submitted) -> None:
        self.query_one("#menu", OptionList).focus()


# ----------------------------------------------------------------------------
# Dialogs
# ----------------------------------------------------------------------------

class SelectOneScreen(DialogScreen[Optional[str]]):
    def __init__(self, title: str, options: List[Tuple[str, str]], current: Optional[str]):
        super().__init__()
        self.title_text = title
        self.options = options
        self.current = current

    def compose(self) -> ComposeResult:
        yield Label(self.title_text, classes="header-text")
        with Center():
            yield _MenuList(*[Option(label, id=key) for key, label in self.options], id="options")
        yield Footer()

    def on_mount(self) -> None:
        menu = self.query_one("#options", OptionList)
        menu.highlighted = next((i for i, (k, _) in enumerate(self.options) if k == self.current), 0)
        menu.focus()

    @on(OptionList.OptionSelected, "#options")
    def _selected(self, event: OptionList.OptionSelected) -> None:
        self.dismiss(event.option.id)


class _CheckList(SelectionList[str]):
    BINDINGS: ClassVar = [
        Binding("down", "cursor_down", "Down", show=True),
        Binding("up", "cursor_up", "Up", show=True),
        Binding("j", "cursor_down", "Down", show=False),
        Binding("k", "cursor_up", "Up", show=False),
        Binding("space", "select", "Toggle", show=True),
        Binding("enter", "screen.confirm", "Confirm", show=True),
        Binding("a", "select_all", "All", show=True),
        Binding("c", "deselect_all", "None", show=True),
    ]

    def action_select_all(self) -> None:
        self.select_all()

    def action_deselect_all(self) -> None:
        self.deselect_all()


class SelectManyScreen(DialogScreen[Optional[List[str]]]):
    def __init__(self, title: str, options: List[Tuple[str, str, bool]]):
        super().__init__()
        self.title_text = title
        self.options = options

    def compose(self) -> ComposeResult:
        yield Label(self.title_text, classes="header-text")
        with Center():
            yield _CheckList(*[Selection(label, key, state) for key, label, state in self.options], id="options")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#options", SelectionList).focus()

    def action_confirm(self) -> None:
        selected = set(self.query_one("#options", SelectionList).selected)
        # Keep the original option order in the result
        self.dismiss([key for key, _, _ in self.options if key in selected])


class InputScreen(DialogScreen[Optional[str]]):
    DEFAULT_CSS = """
    InputScreen .input-content {
        width: 60;
        height: auto;
    }
    """

    def __init__(self, title: str, prompt: str, default: str = ""):
        super().__init__()
        self.title_text = title
        self.prompt = prompt
        self.default = default

    def compose(self) -> ComposeResult:
        yield Label(f"{self.title_text}\n\n{self.prompt}", classes="header-text")
        with Center():
            with Vertical(classes="input-content"):
                yield Input(value=self.default, id="value")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#value", Input).focus()

    @on(Input.Submitted, "#value")
    def _submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value.strip())


class ConfirmScreen(DialogScreen[bool]):
    """Header message with archinstall-style horizontal buttons."""

    BINDINGS: ClassVar = [
        Binding("left", "app.focus_previous", "Left", show=True),
        Binding("right", "app.focus_next", "Right", show=True),
        Binding("h", "app.focus_previous", "Left", show=False),
        Binding("l", "app.focus_next", "Right", show=False),
        Binding("y", "answer(True)", "Yes", show=False),
        Binding("n", "answer(False)", "No", show=False),
    ]

    def __init__(self, title: str, message: str, alert: bool = False):
        super().__init__()
        self.title_text = title
        self.message = message
        self.alert = alert

    def compose(self) -> ComposeResult:
        yield Label(Text(self.title_text, style="bold"), classes="header-text")
        with Center():
            yield Static(self.message, classes="message", markup=False)
        with Horizontal(classes="buttons"):
            if self.alert:
                yield Button("Ok", id="yes")
            else:
                yield Button("Yes", id="yes")
                yield Button("No", id="no")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#yes", Button).focus()

    def action_cancel(self) -> None:
        self.dismiss(False)

    def action_answer(self, value: bool) -> None:
        if not self.alert:
            self.dismiss(value)

    @on(Button.Pressed)
    def _pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")


# ----------------------------------------------------------------------------
# Execution / progress
# ----------------------------------------------------------------------------

class ExecutionScreen(Screen[bool]):
    DEFAULT_CSS = """
    ExecutionScreen #steps {
        width: 40%;
        height: 1fr;
        background: transparent;
    }

    ExecutionScreen #log {
        height: 1fr;
        background: transparent;
        border: none;
        overflow-x: hidden;
    }

    ExecutionScreen #progress {
        height: 1;
        color: white 60%;
    }
    """

    BINDINGS: ClassVar = [
        Binding("enter", "finish", "Finish", show=True),
        Binding("q", "finish", "Finish", show=False),
    ]

    SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    def __init__(self, plan: ExecutionPlan, dry_run: bool = False):
        super().__init__()
        self.plan = plan
        self.dry_run = dry_run
        self.current = 0
        self.done = False
        self.has_errors = False
        self.frame = 0
        self.started = time.time()

    def compose(self) -> ComposeResult:
        mode = "Dry run" if self.dry_run else "Installing"
        yield Label(f" {mode}: {self.plan.config.distro_name} ({len(self.plan.steps)} steps) ", classes="app-header")
        with Vertical(classes="content"):
            yield Label("", id="status", classes="header-text")
            with Horizontal():
                with ScrollableContainer(id="steps"):
                    yield Static("", id="steps-content")
                yield Rule(orientation="vertical")
                with Vertical():
                    yield RichLog(id="log", wrap=True, markup=False, highlight=False, auto_scroll=True)
                    yield Label("", id="progress")
        yield Footer()

    def on_mount(self) -> None:
        self.set_interval(0.1, self._tick)
        self._render_steps()
        self._run_plan()

    @work(thread=True)
    def _run_plan(self) -> None:
        try:
            for event in run_plan(self.plan, dry_run=self.dry_run):
                self.app.call_from_thread(self._on_event, event)
        except Exception as e:
            self.app.call_from_thread(self._fail_runner, str(e))

    def _fail_runner(self, error: str) -> None:
        self.has_errors = True
        self.query_one("#log", RichLog).write(Text(f"Runner Error: {error}", style="bold red"))
        self._finish_plan()

    def _on_event(self, event: ExecutionEvent) -> None:
        log = self.query_one("#log", RichLog)
        progress = self.query_one("#progress", Label)
        self.current = event.step_index

        if event.event_type == "output":
            if event.is_transient or is_progress_line(event.message):
                # Keep download/build progress on one live line instead of flooding the log
                progress.update(event.message)
            else:
                style = "white"
                if event.message.startswith("[EXEC]"):
                    style = "bold cyan"
                elif event.message.startswith("[DRY-RUN]"):
                    style = "bright_yellow"
                elif "error" in event.message.lower():
                    style = "red"
                log.write(Text(event.message, style=style))
        elif event.event_type == "step_start":
            progress.update("")
            log.write(Text(f"==> {event.step.title}", style="bold blue"))
        elif event.event_type == "step_complete":
            progress.update("")
            log.write(Text(f"✓ Completed: {event.step.title} ({event.step.duration:.1f}s)", style="bold green"))
        elif event.event_type == "step_fail":
            self.has_errors = True
            progress.update("")
            log.write(Text(f"✗ ERROR: {event.step.title}", style="bold red"))
            if event.step.error_message:
                log.write(Text(event.step.error_message, style="red"))
        elif event.event_type == "plan_complete":
            self._finish_plan()

        self._render_steps()

    def _finish_plan(self) -> None:
        self.done = True
        self.query_one("#progress", Label).update("")
        self.refresh_bindings()
        self._render_steps()

    def check_action(self, action: str, parameters: tuple[object, ...]) -> bool | None:
        # Only offer "Finish" once the plan is done
        if action == "finish":
            return self.done
        return True

    def _tick(self) -> None:
        self.frame = (self.frame + 1) % len(self.SPINNER)
        if not self.done:
            self._render_steps()

    def _render_steps(self) -> None:
        total = len(self.plan.steps)
        elapsed = int(time.time() - self.started)
        if self.done:
            status = "Finished with errors" if self.has_errors else "Finished successfully"
            status += f" in {elapsed // 60}m {elapsed % 60:02d}s — press Enter to continue"
        else:
            status = f"Step {min(total, self.current + 1)} of {total}  ·  {elapsed // 60}m {elapsed % 60:02d}s"
        self.query_one("#status", Label).update(status)

        text = Text()
        for i, step in enumerate(self.plan.steps):
            if step.status == StepStatus.COMPLETED:
                icon, style = "✓", "green"
            elif step.status == StepStatus.RUNNING:
                icon, style = self.SPINNER[self.frame], "bold bright_yellow"
            elif step.status == StepStatus.FAILED:
                icon, style = "✗", "bold red"
            else:
                icon, style = "·", "white"
            text.append(f"{icon} {i + 1:>2}. {step.title}\n", style=style)
        self.query_one("#steps-content", Static).update(text)

    def action_finish(self) -> None:
        if self.done:
            self.dismiss(not self.has_errors)


# ----------------------------------------------------------------------------
# App
# ----------------------------------------------------------------------------

class TextualPrompter:
    """Prompter that pushes Textual screens. Must run inside an app worker."""

    def __init__(self, app: App):
        self.app = app

    async def select_one(self, title: str, options: List[Tuple[str, str]], current: Optional[str]) -> Optional[str]:
        return await self.app.push_screen_wait(SelectOneScreen(title, options, current))

    async def select_many(self, title: str, options: List[Tuple[str, str, bool]]) -> Optional[List[str]]:
        return await self.app.push_screen_wait(SelectManyScreen(title, options))

    async def ask_text(self, title: str, prompt: str, default: str = "") -> Optional[str]:
        return await self.app.push_screen_wait(InputScreen(title, prompt, default))

    async def confirm(self, title: str, message: str) -> bool:
        return bool(await self.app.push_screen_wait(ConfirmScreen(title, message)))

    async def notify(self, title: str, message: str) -> None:
        await self.app.push_screen_wait(ConfirmScreen(title, message, alert=True))


class PostInstallApp(App[int]):
    CSS = APP_CSS
    ENABLE_COMMAND_PALETTE = False

    BINDINGS: ClassVar = [
        Binding("f1", "toggle_help", "Help", show=True),
        Binding("ctrl+q", "quit", "Quit", show=True, priority=True),
    ]

    def __init__(self, state: MenuState, dry_run: bool = False):
        super().__init__(ansi_color=True)
        self.state = state
        self.dry_run = dry_run
        self.ui = TextualPrompter(self)

    def on_mount(self) -> None:
        self._main_flow()

    def action_toggle_help(self) -> None:
        from textual.widgets import HelpPanel

        panels = self.screen.query(HelpPanel)
        if panels:
            panels.remove()
        else:
            self.screen.mount(HelpPanel())

    @work(exclusive=True)
    async def _main_flow(self) -> None:
        focus_key: Optional[str] = None

        while True:
            key = await self.push_screen_wait(MainMenuScreen(self.state, focus_key))
            if key is None:
                continue
            focus_key = key
            item = next((it for it in build_menu_items(self.state) if it.key == key), None)

            if key == "action_save":
                await save_config(self.state, self.ui)
                continue
            if key == "action_load":
                await load_config(self.state, self.ui)
                continue
            if item is None:
                continue

            action = await handle_item_select(self.state, item, self.ui)
            if action == "exit":
                self.exit(0)
                return
            if action != "install":
                continue

            plan = ExecutionPlan(self.state.config, self.state.base_dir, self.state.sysinfo)
            if not plan.steps:
                await self.ui.notify("Nothing to Install", "The current configuration has no steps to run.")
                continue
            if not await self.ui.confirm("Confirm Post-Installation Setup", install_summary(self.state.config, plan)):
                continue

            success = await self.push_screen_wait(ExecutionScreen(plan, dry_run=self.dry_run))
            title = "Installation Complete!" if success else "Installation Completed with Warnings"
            await self.ui.notify(title, FINISH_MESSAGE)
            self.exit(0 if success else 1)
            return


def run_textual_tui(
    base_dir: Path,
    config_path: Optional[str] = None,
    dry_run: bool = False,
    distro_override: Optional[str] = None,
) -> int:
    from core.tui.app import load_initial_state

    state = load_initial_state(base_dir, config_path, distro_override)
    result = PostInstallApp(state, dry_run=dry_run).run()
    return result if isinstance(result, int) else 0
