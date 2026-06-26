#!/usr/bin/env python3
"""Locate, back up, and restore complete kakeibo SQLite databases safely."""
from __future__ import annotations

import argparse
import os
import socket
import sqlite3
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = REPO_ROOT / "backend"
sys.path.insert(0, str(BACKEND_ROOT))

from app.data_paths import backup_sqlite_database  # noqa: E402


@dataclass(frozen=True)
class DatabaseInfo:
    path: Path
    transaction_count: int
    crypto_config_count: int
    size_bytes: int
    modified_at: datetime


def configured_database_path() -> Path:
    explicit = os.getenv("KAKEIBO_DB_PATH", "").strip()
    if explicit:
        path = Path(explicit).expanduser()
        return path if path.is_absolute() else Path.cwd() / path

    configured_dir = os.getenv("KAKEIBO_DATA_DIR", "").strip()
    data_dir = (
        Path(configured_dir).expanduser()
        if configured_dir
        else Path.home() / ".kakeibo"
    )
    if not data_dir.is_absolute():
        data_dir = Path.cwd() / data_dir
    return data_dir / "data.db"


def _table_count(connection: sqlite3.Connection, table: str) -> int:
    quoted = table.replace('"', '""')
    row = connection.execute(f'SELECT COUNT(*) FROM "{quoted}"').fetchone()
    return int(row[0]) if row else 0


def inspect_database(path: Path) -> DatabaseInfo | None:
    path = path.expanduser().resolve()
    if not path.is_file():
        return None

    try:
        uri = f"{path.as_uri()}?mode=ro"
        with sqlite3.connect(uri, uri=True) as connection:
            tables = {
                str(row[0])
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            if not {"encrypted_transactions", "app_crypto_config"}.intersection(tables):
                return None

            transaction_count = (
                _table_count(connection, "encrypted_transactions")
                if "encrypted_transactions" in tables
                else 0
            )
            crypto_config_count = (
                _table_count(connection, "app_crypto_config")
                if "app_crypto_config" in tables
                else 0
            )
    except sqlite3.DatabaseError:
        return None

    stat = path.stat()
    return DatabaseInfo(
        path=path,
        transaction_count=transaction_count,
        crypto_config_count=crypto_config_count,
        size_bytes=stat.st_size,
        modified_at=datetime.fromtimestamp(stat.st_mtime),
    )


def candidate_databases() -> list[DatabaseInfo]:
    home = Path.home().resolve()
    candidates: set[Path] = {
        configured_database_path().expanduser().resolve(),
        (BACKEND_ROOT / "data.db").resolve(),
    }

    skip_names = {
        ".git",
        ".venv",
        "node_modules",
        "Library",
        ".Trash",
        ".cache",
        "Caches",
    }

    for root, directories, files in os.walk(home, topdown=True):
        root_path = Path(root)
        try:
            depth = len(root_path.relative_to(home).parts)
        except ValueError:
            continue

        directories[:] = [
            name
            for name in directories
            if name not in skip_names and not name.startswith(".venv")
        ]
        if depth >= 8:
            directories.clear()

        for filename in files:
            if filename == "data.db" or filename.startswith("data.db.bak"):
                candidates.add(root_path / filename)

    infos = [info for path in candidates if (info := inspect_database(path))]
    return sorted(
        infos,
        key=lambda info: (info.transaction_count, info.modified_at),
        reverse=True,
    )


def format_size(size: int) -> str:
    if size < 1024:
        return f"{size} B"
    if size < 1024 * 1024:
        return f"{size / 1024:.1f} KiB"
    return f"{size / (1024 * 1024):.1f} MiB"


def print_info(info: DatabaseInfo, *, prefix: str = "") -> None:
    print(f"{prefix}取引件数 : {info.transaction_count}")
    print(f"{prefix}暗号設定 : {info.crypto_config_count}")
    print(f"{prefix}サイズ   : {format_size(info.size_bytes)}")
    print(f"{prefix}更新日時 : {info.modified_at.isoformat(sep=' ', timespec='seconds')}")
    print(f"{prefix}パス     : {info.path}")


def port_is_open(port: int) -> bool:
    with socket.socket() as connection:
        connection.settimeout(0.2)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def require_stopped_application() -> None:
    active = [port for port in (5173, 8000) if port_is_open(port)]
    if active:
        joined = ", ".join(str(port) for port in active)
        raise SystemExit(
            f"アプリが起動中です（TCP {joined}）。Ctrl-Cで停止してから再実行してください。"
        )


def backup_directory() -> Path:
    target = configured_database_path()
    directory = target.parent / "backups"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory


def create_backup(source: Path, label: str = "manual") -> Path:
    info = inspect_database(source)
    if info is None:
        raise SystemExit(f"kakeibo DBとして確認できません: {source}")

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    destination = backup_directory() / f"data.db.{label}.{timestamp}"
    backup_sqlite_database(info.path, destination)
    return destination


def command_status(_args: argparse.Namespace) -> None:
    target = configured_database_path()
    print(f"現在の保存先: {target}")
    info = inspect_database(target)
    if info is None:
        print("状態: DBなし、またはkakeibo DBとして確認できません")
        return
    print_info(info)


def command_scan(_args: argparse.Namespace) -> None:
    infos = candidate_databases()
    if not infos:
        print("kakeibo形式のDB候補は見つかりませんでした。")
        return

    print("kakeibo DB候補（取引件数の多い順）")
    for index, info in enumerate(infos, start=1):
        print()
        print(f"[{index}]")
        print_info(info, prefix="  ")


def command_backup(_args: argparse.Namespace) -> None:
    require_stopped_application()
    source = configured_database_path()
    destination = create_backup(source)
    print(f"バックアップを作成しました: {destination}")


def command_restore(args: argparse.Namespace) -> None:
    require_stopped_application()

    source = Path(args.source).expanduser().resolve()
    source_info = inspect_database(source)
    if source_info is None:
        raise SystemExit(f"kakeibo形式のDBではありません: {source}")
    if source_info.transaction_count > 0 and source_info.crypto_config_count != 1:
        raise SystemExit(
            "取引があるのに暗号設定が1件ではありません。復号不能を避けるため復元を中止します。"
        )

    target = configured_database_path().expanduser().resolve()
    if source == target:
        print("指定DBは既に現在の保存先です。変更しません。")
        print_info(source_info)
        return

    if target.exists():
        backup_path = create_backup(target, label="before-restore")
        print(f"現在DBを退避しました: {backup_path}")

    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup_sqlite_database(source, target)
    restored = inspect_database(target)
    if restored is None:
        raise SystemExit("復元後DBの検証に失敗しました")

    print("復元しました。")
    print_info(restored)
    print("次回起動時は、復元元データで使用していたパスフレーズを入力してください。")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="kakeibo暗号化DBの検索・バックアップ・復元"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    status_parser = subparsers.add_parser("status", help="現在DBの状態を表示")
    status_parser.set_defaults(handler=command_status)

    scan_parser = subparsers.add_parser("scan", help="ホーム内の旧DB候補を検索")
    scan_parser.set_defaults(handler=command_scan)

    backup_parser = subparsers.add_parser("backup", help="現在DBをバックアップ")
    backup_parser.set_defaults(handler=command_backup)

    restore_parser = subparsers.add_parser(
        "restore", help="指定した旧DBで現在DBを安全に置換"
    )
    restore_parser.add_argument("source", help="復元元data.dbのパス")
    restore_parser.set_defaults(handler=command_restore)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
