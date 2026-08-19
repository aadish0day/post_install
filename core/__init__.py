"""
Post-installation automation core package.
"""

from core.config import PostInstallConfig
from core.detector import SystemInfo, detect_system
from core.runner import ExecutionPlan, Step, StepStatus, run_plan

__all__ = [
    "ExecutionPlan",
    "PostInstallConfig",
    "Step",
    "StepStatus",
    "SystemInfo",
    "detect_system",
    "run_plan",
]
