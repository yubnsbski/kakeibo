# kakeibo frontend

Vite + React + TypeScript の最小フロントエンド。
ブラウザ側で AES-GCM 暗号化を行うことで、サーバー・開発者がレシート画像の中身を見られない設計を検証する。

## 起動

```
cd frontend
npm install
npm run dev
```

`http://localhost:5173` を開く。

## 構成

- `src/encrypt.ts` — Web Crypto API による AES-GCM 暗号化/復号ユーティリティ
- `src/App.tsx` — 画像アップロード → フロント暗号化 → 復号プレビュー
- 鍵はメモリ上のみで保持し、サーバーへは送信しない

## サーバー連携（未実装）

`src/server.ts` の `/classify` に暗号化済み blob を送る場合は、
鍵管理（パスフレーズ派生 or ローカル保存）を別途決める必要がある。
