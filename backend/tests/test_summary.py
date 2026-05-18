"""Summary API のテスト."""
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


def _create_tx(client, **kw):
    base = {
        "merchant_raw": "T", "merchant_normalized": "T", "items_text": "",
        "screening_category": None, "needs_review": False, "reason": "",
        "confidence": 0, "amount": 0, "purchased_at": "2026-05-17",
        "status": "manually_added",
    }
    base.update(kw)
    return client.post("/api/transactions", json=base).json()


def test_category_summary_uses_header_when_no_items(client):
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-10")
    _create_tx(client, amount=500, screening_category="酒類", purchased_at="2026-05-12")
    _create_tx(client, amount=300, screening_category="食費", purchased_at="2026-05-20")

    r = client.get("/api/summary/category?ym=2026-05")
    data = r.json()
    by = {s["category"]: s["amount"] for s in data["slices"]}
    assert by["食費"] == 1300
    assert by["酒類"] == 500
    assert data["total"] == 1800


def test_category_summary_uses_items_when_present(client):
    tx = _create_tx(client, amount=0)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "A", "amount": 100, "category": "食費"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "B", "amount": 200, "category": "酒類"})

    r = client.get("/api/summary/category?ym=2026-05")
    by = {s["category"]: s["amount"] for s in r.json()["slices"]}
    assert by["食費"] == 100
    assert by["酒類"] == 200


def test_category_summary_excludes_other_months(client):
    _create_tx(client, amount=500, screening_category="食費", purchased_at="2026-04-15")
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-15")

    r = client.get("/api/summary/category?ym=2026-05")
    by = {s["category"]: s["amount"] for s in r.json()["slices"]}
    assert by["食費"] == 1000  # 4月分は除外


def test_monthly_summary(client):
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-10")
    _create_tx(client, amount=2000, screening_category="食費", purchased_at="2026-04-10")

    r = client.get("/api/summary/monthly?months=6")
    data = r.json()
    assert data["months"] == 6
    assert len(data["slices"]) == 6
    by_ym = {s["ym"]: s["total"] for s in data["slices"]}
    assert by_ym.get("2026-05") == 1000
    assert by_ym.get("2026-04") == 2000
