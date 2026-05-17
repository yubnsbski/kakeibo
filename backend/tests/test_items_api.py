"""明細単位カテゴリ分類 (C4) のテスト."""
from __future__ import annotations
import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch, tmp_path):
    db_file = tmp_path / "test.db"
    monkeypatch.setenv("KAKEIBO_DB_PATH", str(db_file))
    import importlib
    from app import database, main
    importlib.reload(database)
    importlib.reload(main)
    database.create_db_and_tables()
    with TestClient(main.app) as c:
        yield c


def _create_tx(client, **overrides):
    base = {
        "merchant_raw": "テスト",
        "merchant_normalized": "テスト",
        "items_text": "",
        "screening_category": None,
        "needs_review": False,
        "reason": "",
        "confidence": 0,
        "amount": 0,
        "purchased_at": "2026-05-17",
        "status": "manually_added",
    }
    base.update(overrides)
    r = client.post("/api/transactions", json=base)
    assert r.status_code == 201
    return r.json()


def test_add_items_recalculates_header(client):
    tx = _create_tx(client, amount=0)
    tx_id = tx["id"]
    # 明細を3つ追加
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "おにぎり", "amount": 180, "category": "食費"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "ビール", "amount": 300, "category": "酒類"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "弁当", "amount": 500, "category": "食費"})

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 980, f"expected 980, got {data['amount']}"
    # 食費 (180+500=680) > 酒類 (300) → 主カテゴリは食費
    assert data["screening_category"] == "食費"
    assert len(data["items"]) == 3


def test_item_update_recalculates_header(client):
    tx = _create_tx(client)
    tx_id = tx["id"]
    r = client.post(f"/api/transactions/{tx_id}/items",
                    json={"name": "X", "amount": 100, "category": "食費"})
    item_id = r.json()["id"]

    client.patch(f"/api/transactions/{tx_id}/items/{item_id}",
                 json={"amount": 500, "category": "酒類"})

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 500
    assert data["screening_category"] == "酒類"


def test_item_delete_recalculates_header(client):
    tx = _create_tx(client)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "A", "amount": 100, "category": "食費"})
    r = client.post(f"/api/transactions/{tx_id}/items",
                    json={"name": "B", "amount": 200, "category": "酒類"})
    item_id = r.json()["id"]

    client.delete(f"/api/transactions/{tx_id}/items/{item_id}")

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 100
    assert data["screening_category"] == "食費"


def test_empty_items_keeps_header_amount(client):
    """明細空ならヘッダはそのまま."""
    tx = _create_tx(client, amount=1500, screening_category="食費")
    tx_id = tx["id"]
    r = client.get(f"/api/transactions/{tx_id}")
    assert r.json()["amount"] == 1500
    assert r.json()["screening_category"] == "食費"
    assert r.json()["items"] == []


def test_unclassified_items_yield_null_category(client):
    """全明細が未分類ならヘッダカテゴリも null."""
    tx = _create_tx(client)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "X", "amount": 100, "category": None})
    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["screening_category"] is None
    assert data["amount"] == 100


def test_item_tax_amount_auto_calculated(client):
    """食費は8%、酒類は10%."""
    tx = _create_tx(client)
    tx_id = tx["id"]
    r1 = client.post(f"/api/transactions/{tx_id}/items",
                     json={"name": "おにぎり", "amount": 108, "category": "食費"})
    r2 = client.post(f"/api/transactions/{tx_id}/items",
                     json={"name": "ビール", "amount": 110, "category": "酒類"})
    assert r1.json()["tax_amount"] == 8, r1.json()
    assert r2.json()["tax_amount"] == 10, r2.json()
