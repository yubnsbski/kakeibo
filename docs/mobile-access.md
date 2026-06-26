# スマホから安全に接続する

## なぜHTTPでは動かないか

このアプリはブラウザのWeb Crypto APIで取引を暗号化・復号します。
`localhost`以外のLAN IPをHTTPで開いた場合、ブラウザは安全なコンテキストとして扱わず、Web Crypto APIを利用できません。

そのためスマホでは、次のようなHTTPS URLを使用します。

```text
https://192.168.x.x:5173/
```

従来の次のURLは、証明書設定ページへの案内だけを表示します。

```text
http://192.168.x.x:5173/
```

## 起動

Macとスマホを同じWi-Fiへ接続し、Macで実行します。

```bash
cd "$HOME/src/kakeibo"
bash scripts/start_mobile.sh
```

起動時に現在のLAN IPを自動検出し、次の2つのURLを表示します。

- 証明書設定: `http://LAN-IP:5174/`
- 家計簿: `https://LAN-IP:5173/`

## iPhone / iPad 初回設定

1. Safariで証明書設定URLを開く。
2. 「公開CA証明書をダウンロード」を押す。
3. 「設定」に表示されるダウンロード済みプロファイルをインストールする。
4. `設定 → 一般 → 情報 → 証明書信頼設定`を開く。
5. `Kakeibo Local CA`の「ルート証明書を全面的に信頼」を有効にする。
6. 証明書設定ページへ戻り、「HTTPSで家計簿を開く」を押す。

## Android 初回設定

端末やOSによって名称は異なります。公開CA証明書をダウンロードし、セキュリティ設定の「CA証明書をインストール」から追加した後、HTTPS URLを開きます。

## 2回目以降

証明書が有効な間は、次だけで起動できます。

```bash
cd "$HOME/src/kakeibo"
bash scripts/start_mobile.sh
```

同じHTTPS URLをブックマークできます。

## IPアドレスが変わった場合

`start_mobile.sh`は起動時にサーバー証明書を現在のIP向けに更新します。ローカルCAは再作成しないため、通常はスマホへCA証明書を再インストールする必要はありません。

## 接続できない場合

- Macとスマホが同じWi-Fiか確認する。
- ゲストWi-Fiや端末分離（AP isolation）が有効でないか確認する。
- MacのファイアウォールでNode/Pythonの受信接続を許可する。
- 起動時に表示されたLAN IPを使う。固定の`192.168.3.5`とは限らない。
- VPNを一時的に切り、LANへの経路を確認する。

## 証明書ファイル

```text
~/.kakeibo/certs/kakeibo-local-ca.cer    公開CA証明書（スマホへ渡してよい）
~/.kakeibo/certs/kakeibo-local-ca.key    CA秘密鍵（共有禁止）
~/.kakeibo/certs/kakeibo-server.key      サーバー秘密鍵（共有禁止）
```

公開CA証明書以外はMac外へ出さないでください。
