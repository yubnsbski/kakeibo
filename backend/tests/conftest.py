"""Shared pytest fixtures."""
from __future__ import annotations
import json
from pathlib import Path
import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_REPO_ROOT = _BACKEND_ROOT.parent
FIXTURES_DIR = _REPO_ROOT / "fixtures" / "receipts"


def load_fixture_cases(filename: str) -> list[dict]:
    path = FIXTURES_DIR / filename
    return json.loads(path.read_text(encoding="utf-8"))
