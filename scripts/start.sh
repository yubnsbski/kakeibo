#!/usr/bin/env bash
set -u

REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "[1/6] 既存プロセス停止"
echo "============================================================"
pkill -9 -f uvicorn 2>/dev/null || true
pkill -9 -f vite 2>/dev/null || true
pkill -9 -f "node.*vite" 2>/dev/null || true
sleep 2

echo
echo "============================================================"
echo "[2/6] frontend proxy 確認"
echo "============================================================"
grep -n "target:" "$REPO/frontend/vite.config.ts" || true

echo
echo "============================================================"
echo "[3/6] backend 起動 :8000"
echo "============================================================"
(cd "$REPO/backend" && nohup .venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo
echo "============================================================"
echo "[4/6] frontend 起動 :5173"
echo "============================================================"
(cd "$REPO/frontend" && nohup npm run dev -- --host 0.0.0.0 > /tmp/vite.log 2>&1 &)
sleep 8

echo
echo "============================================================"
echo "[5/6] LISTEN 確認"
echo "============================================================"
ss -tlnp 2>&1 | grep -E ":5173|:8000" || echo "(LISTEN なし)"

echo
echo "============================================================"
echo "[6/6] API確認"
echo "============================================================"

echo
echo "--- backend health ---"
curl -i http://127.0.0.1:8000/api/health || true

echo
echo "--- backend crypto config GET ---"
curl -i http://127.0.0.1:8000/api/crypto/config || true

echo
echo "--- vite root ---"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5173/ || true

echo
echo "--- vite proxy health ---"
curl -i http://127.0.0.1:5173/api/health || true

echo
echo "--- vite proxy crypto config GET ---"
curl -i http://127.0.0.1:5173/api/crypto/config || true

echo
echo "============================================================"
echo "ログ確認:"
echo "  tail -80 /tmp/uvicorn.log"
echo "  tail -80 /tmp/vite.log"
echo "============================================================"
