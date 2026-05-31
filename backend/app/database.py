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

# (name, desc, tax_rate, sort_order, is_income)
_INITIAL_CATEGORIES = [
    # 支出 - 既存9
    ("食費", "スーパー, コンビニ, 弁当, 食品", 8, 1, False),
    ("酒類", "ビール, ワイン, 日本酒, チューハイ", 10, 2, False),
    ("外食", "レストラン, カフェ, 居酒屋", 10, 3, False),
    ("日用品", "ドラッグストア, 洗剤, トイレ, キッチン", 10, 4, False),
    ("交通費", "電車, バス, タクシー, ガソリン, 駐車場", 10, 5, False),
    ("医療費", "病院, 薬局, 医薬品, 診察", 10, 6, False),
    ("娯楽費", "書店, 映画, ゲーム, 趣味, レジャー", 10, 7, False),
    ("衣料費", "アパレル, 靴, ファッション, クリーニング", 10, 8, False),
    ("その他", "判断できないもの", 10, 9, False),
    # 支出 - 新規3
    ("家賃", "家賃, 住居費", 10, 10, False),
    ("光熱費", "電気, ガス, 水道", 10, 11, False),
    ("通信費", "スマホ, インターネット, 固定電話", 10, 12, False),
    # 収入
    ("給与", "本業の給与収入", 0, 101, True),
    ("副収入", "副業, ボーナス, 副業収入", 0, 102, True),
    ("その他収入", "還付金, 贈与, 投資収益等", 0, 103, True),
]


def create_db_and_tables() -> None:
    from . import models  # noqa: F401
    from . import crypto_models  # noqa: F401  (E2E暗号テーブル登録)
    SQLModel.metadata.create_all(engine)
    _seed_categories()


def _seed_categories() -> None:
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            existing_names = {c.name for c in session.exec(select(CategoryMaster)).all()}
            for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
                if name not in existing_names:
                    session.add(CategoryMaster(
                        name=name, description=desc, tax_rate=rate,
                        sort_order=order, is_income=is_income,
                    ))
            session.commit()
            return
        for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(
                name=name, description=desc, tax_rate=rate,
                sort_order=order, is_income=is_income,
            ))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
