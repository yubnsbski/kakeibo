"""SQLite + SQLModel database wiring.

DB file location:
    Default: backend/data.db
    Override via KAKEIBO_DB_PATH env var (useful for tests).

create_db_and_tables() is called from FastAPI lifespan; pytest fixtures
override the engine to use in-memory or tmp_path databases.
"""
from __future__ import annotations

import os
from collections.abc import Generator
from pathlib import Path

from sqlmodel import Session, SQLModel, create_engine

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_ROOT / "data.db"

DB_PATH = os.getenv("KAKEIBO_DB_PATH", str(_DEFAULT_DB_PATH))
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(
    DB_URL,
    echo=False,
    connect_args={"check_same_thread": False},
)


def create_db_and_tables() -> None:
    """Create all tables defined in models.py. Idempotent."""
    # Import models so SQLModel.metadata sees all table classes
    from . import models  # noqa: F401

    SQLModel.metadata.create_all(engine)


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency for a per-request DB session."""
    with Session(engine) as session:
        yield session
