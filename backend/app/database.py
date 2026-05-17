"""SQLite + SQLModel database wiring with seeding."""
from __future__ import annotations
import os
from collections.abc import Generator
from pathlib import Path
from sqlmodel import Session, SQLModel, create_engine, select

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_ROOT / "data.db"
DB_PATH = os.getenv("KAKEIBO_DB_PATH", str(_DEFAULT_DB_PATH))
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DB_URL, echo=False, connect_args={"check_same_thread": False})

_INITIAL_CATEGORIES = [
    ("食費", "スーパー, コンビニ, 弁当, 食品", 8, 1),
    ("酒類", "ビール, ワイン, 日本酒, チューハイ", 10, 2),
    ("外食", "レストラン, カフェ, 居酒屋", 10, 3),
    ("日用品", "ドラッグストア, 洗剤, トイレ, キッチン", 10, 4),
    ("交通費", "電車, バス, タクシー, ガソリン, 駐車場", 10, 5),
    ("医療費", "病院, 薬局, 医薬品, 診察", 10, 6),
    ("娯楽費", "書店, 映画, ゲーム, 趣味, レジャー", 10, 7),
    ("衣料費", "アパレル, 靴, ファッション, クリーニング", 10, 8),
    ("その他", "判断できないもの", 10, 99),
]


def create_db_and_tables() -> None:
    from . import models  # noqa: F401
    SQLModel.metadata.create_all(engine)
    _seed_categories()


def _seed_categories() -> None:
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            return
        for name, desc, rate, order in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(name=name, description=desc, tax_rate=rate, sort_order=order))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
