#!/usr/bin/env python3
"""
Post-Installation Automation Suite (Archinstall TUI Experience)
Universal post-installation orchestrator for Arch Linux, Debian/Ubuntu, Fedora, Kali, and Termux.

Usage:
  ./install.sh                # Launch interactive Archinstall TUI
  python3 install.py          # Direct Python invocation
  python3 install.py --dry-run
  python3 install.py --config config.json
  python3 install.py --distro arch
  python3 install.py --save-config default.json
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

# Add script root to sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from core.config import PostInstallConfig
from core.detector import detect_system
from core.runner import ExecutionPlan, StepStatus, run_plan
from core.tui.app import run_tui


def run_headless_cli(config: PostInstallConfig, base_dir: Path, dry_run: bool = False) -> int:
    """Non-interactive CLI mode for automated pipelines or scripts."""
    print("=" * 60)
    print(" POST-INSTALLATION SUITE - HEADLESS EXECUTION")
    print("=" * 60)
    print(f"Target Distribution: {config.distro_name} ({config.distro})")
    print(f"Mode:                {'DRY-RUN (Simulation)' if dry_run else 'LIVE EXECUTION'}")
    print("=" * 60)

    sysinfo = detect_system()
    plan = ExecutionPlan(config, base_dir, sysinfo)

    print(f"\nPlanned Steps ({len(plan.steps)} total):")
    for i, step in enumerate(plan.steps, 1):
        print(f"  {i:2d}. {step.title}")

    print("\nStarting execution...\n")
    has_errors = False
    start_time = time.time()

    for event in run_plan(plan, dry_run=dry_run):
        if event.event_type == "step_start":
            print(f"\n==> [{event.step_index + 1}/{len(plan.steps)}] {event.step.title}")
        elif event.event_type == "output":
            print(f"    {event.message}")
        elif event.event_type == "step_complete":
            print(f"    ✓ Success ({event.step.duration:.1f}s)")
        elif event.event_type == "step_fail":
            has_errors = True
            print(f"    ✖ FAILED: {event.step.title}")
            if event.step.error_message:
                print(f"      {event.step.error_message}")

    total_time = time.time() - start_time
    print("\n" + "=" * 60)
    if has_errors:
        print(f" Installation finished with ERRORS in {total_time:.1f}s.")
        return 1
    else:
        print(f" Installation COMPLETED SUCCESSFULLY in {total_time:.1f}s!")
        print(" Please restart your session or reboot for all changes to take effect.")
        print("=" * 60)
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Post-Installation Automation Suite with Archinstall-style TUI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./install.sh                              # Start Archinstall interactive TUI
  python3 install.py --dry-run              # Preview plan in TUI without changes
  python3 install.py --config my_conf.json  # Run unattended installation with JSON
  python3 install.py --save-config out.json # Export auto-detected preset to JSON
        """
    )
    parser.add_argument("--config", "-c", type=str, help="Path to JSON configuration profile")
    parser.add_argument("--dry-run", "-d", action="store_true", help="Simulate execution without modifying the system")
    parser.add_argument("--distro", choices=["arch", "debian", "fedora", "kali", "termux"], help="Override detected distribution")
    parser.add_argument("--save-config", type=str, help="Export default/detected configuration to JSON file and exit")
    parser.add_argument("--headless", "--cli", action="store_true", help="Run in non-interactive CLI mode")

    args = parser.parse_args()

    # If user wants to save default config
    if args.save_config:
        sysinfo = detect_system()
        cfg = PostInstallConfig.default_for_system(sysinfo)
        if args.distro:
            cfg.set_distro(args.distro)
        cfg.save_json(args.save_config)
        print(f"Configuration saved to: {os.path.abspath(args.save_config)}")
        return 0

    # If running headless CLI or if not connected to a TTY
    is_tty = sys.stdin.isatty() and sys.stdout.isatty()
    if args.headless or (args.config and not is_tty) or not is_tty:
        if args.config and os.path.isfile(args.config):
            cfg = PostInstallConfig.load_json(args.config)
        else:
            cfg = PostInstallConfig.default_for_system()
        if args.distro:
            cfg.set_distro(args.distro)
        return run_headless_cli(cfg, SCRIPT_DIR, dry_run=args.dry_run)

    # Launch full Archinstall-style Curses TUI
    return run_tui(
        base_dir=SCRIPT_DIR,
        config_path=args.config,
        dry_run=args.dry_run,
        distro_override=args.distro
    )


if __name__ == "__main__":
    sys.exit(main())
