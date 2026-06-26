"""Stable local data paths and safe SQLite migration helpers."""
from __future__ import annotations

import os
import sqlite3
from collections.abc import Mapping
from pathlib import Path

_DEFAULT_DATA_DIR_NAME = ".kakeibo"
_DEFAULT_DB_NAME = "data.db"


def _absolute_path(path: Path) -> Path:
    expanded = path.expanduser()
    return expanded if expanded.is_absolute() else (Path.cwd() / expanded)


def backup_sqlite_database(source: Path, destination: Path) -> None:
    """Create a consistent SQLite snapshot and atomically replace destination.

    SQLite's backup API includes committed WAL contents and avoids copying a
    partially-written database file. The source is never modified.
    """
    source = _absolute_path(source)
    destination = _absolute_path(destination)

    if not source.is_file():
        raise FileNotFoundError(f"database not found: {source}")

    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = destination.with_name(
        f".{destination.name}.tmp-{os.getpid()}"
    )
    temporary.unlink(missing_ok=True)

    try:
        source_uri = f"{source.resolve().as_uri()}?mode=ro"
        with sqlite3.connect(source_uri, uri=True) as source_connection:
            with sqlite3.connect(temporary) as destination_connection:
                source_connection.backup(destination_connection)
                result = destination_connection.execute(
                    "PRAGMA integrity_check"
                ).fetchone()
                if not result or result[0] != "ok":
                    raise sqlite3.DatabaseError(
                        f"backup integrity check failed: {result}"
                    )

        os.replace(temporary, destination)
        try:
            destination.chmod(0o600)
        except OSError:
            # Some filesystems do not support POSIX permissions.
            pass
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def migrate_legacy_database(source: Path, destination: Path) -> bool:
    """Copy a legacy repository-local DB once, without overwriting a target."""
    source = _absolute_path(source)
    destination = _absolute_path(destination)

    if destination.exists() or not source.is_file():
        return False

    backup_sqlite_database(source, destination)
    return True


def resolve_database_path(
    backend_root: Path,
    *,
    home: Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> Path:
    """Resolve the DB path, preferring explicit overrides then stable home data.

    Environment precedence:
      1. KAKEIBO_DB_PATH (full database path)
      2. KAKEIBO_DATA_DIR (directory containing data.db)
      3. ~/.kakeibo/data.db

    When the stable target does not yet exist, backend/data.db from the current
    clone is copied with SQLite's backup API. Existing targets are never
    overwritten automatically.
    """
    env = os.environ if environ is None else environ

    explicit_path = env.get("KAKEIBO_DB_PATH", "").strip()
    if explicit_path:
        resolved = _absolute_path(Path(explicit_path))
        resolved.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        return resolved

    effective_home = Path.home() if home is None else home
    configured_dir = env.get("KAKEIBO_DATA_DIR", "").strip()
    data_dir = (
        _absolute_path(Path(configured_dir))
        if configured_dir
        else _absolute_path(effective_home / _DEFAULT_DATA_DIR_NAME)
    )
    data_dir.mkdir(parents=True, exist_ok=True, mode=0o700)

    destination = data_dir / _DEFAULT_DB_NAME
    legacy = _absolute_path(backend_root / _DEFAULT_DB_NAME)
    migrate_legacy_database(legacy, destination)
    return destination
