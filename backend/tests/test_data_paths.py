from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from app.data_paths import (
    backup_sqlite_database,
    migrate_legacy_database,
    resolve_database_path,
)


class DataPathTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def _create_database(self, path: Path, value: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(path) as connection:
            connection.execute("CREATE TABLE marker (value TEXT NOT NULL)")
            connection.execute("INSERT INTO marker(value) VALUES (?)", (value,))
            connection.commit()

    def _read_value(self, path: Path) -> str:
        with sqlite3.connect(path) as connection:
            row = connection.execute("SELECT value FROM marker").fetchone()
        self.assertIsNotNone(row)
        return str(row[0])

    def test_backup_creates_consistent_snapshot(self) -> None:
        source = self.root / "source.db"
        destination = self.root / "target" / "data.db"
        self._create_database(source, "old-data")

        backup_sqlite_database(source, destination)

        self.assertEqual(self._read_value(destination), "old-data")
        self.assertEqual(self._read_value(source), "old-data")

    def test_legacy_database_is_migrated_only_when_target_is_missing(self) -> None:
        source = self.root / "repo" / "backend" / "data.db"
        destination = self.root / "home" / ".kakeibo" / "data.db"
        self._create_database(source, "legacy")

        self.assertTrue(migrate_legacy_database(source, destination))
        self.assertEqual(self._read_value(destination), "legacy")

        self._create_database(self.root / "replacement.db", "replacement")
        self.assertFalse(migrate_legacy_database(self.root / "replacement.db", destination))
        self.assertEqual(self._read_value(destination), "legacy")

    def test_default_resolution_migrates_repository_database(self) -> None:
        backend_root = self.root / "repo" / "backend"
        legacy = backend_root / "data.db"
        home = self.root / "home"
        self._create_database(legacy, "legacy")

        resolved = resolve_database_path(backend_root, home=home, environ={})

        self.assertEqual(resolved, home / ".kakeibo" / "data.db")
        self.assertEqual(self._read_value(resolved), "legacy")

    def test_explicit_database_path_takes_priority(self) -> None:
        backend_root = self.root / "repo" / "backend"
        explicit = self.root / "custom" / "kakeibo.sqlite3"

        resolved = resolve_database_path(
            backend_root,
            home=self.root / "home",
            environ={"KAKEIBO_DB_PATH": str(explicit)},
        )

        self.assertEqual(resolved, explicit)
        self.assertTrue(explicit.parent.is_dir())
        self.assertFalse((self.root / "home" / ".kakeibo" / "data.db").exists())

    def test_configured_data_directory_is_supported(self) -> None:
        backend_root = self.root / "repo" / "backend"
        data_dir = self.root / "external-data"

        resolved = resolve_database_path(
            backend_root,
            home=self.root / "home",
            environ={"KAKEIBO_DATA_DIR": str(data_dir)},
        )

        self.assertEqual(resolved, data_dir / "data.db")
        self.assertTrue(data_dir.is_dir())


if __name__ == "__main__":
    unittest.main()
