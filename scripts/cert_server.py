#!/usr/bin/env python3
"""Minimal HTTP bootstrap server for installing the public local CA certificate."""
from __future__ import annotations

import argparse
import html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


class CertificateHandler(BaseHTTPRequestHandler):
    certificate_path: Path
    app_url: str

    def _send_bytes(
        self,
        status: int,
        body: bytes,
        *,
        content_type: str,
        disposition: str | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if disposition:
            self.send_header("Content-Disposition", disposition)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlparse(self.path).path

        if path == "/health":
            self._send_bytes(200, b"ok\n", content_type="text/plain; charset=utf-8")
            return

        if path == "/kakeibo-local-ca.cer":
            body = self.certificate_path.read_bytes()
            self._send_bytes(
                200,
                body,
                content_type="application/x-x509-ca-cert",
                disposition='attachment; filename="kakeibo-local-ca.cer"',
            )
            return

        if path not in {"/", "/index.html"}:
            self._send_bytes(404, b"not found\n", content_type="text/plain")
            return

        escaped_app_url = html.escape(self.app_url, quote=True)
        document = f"""<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>kakeibo スマホ接続設定</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      max-width: 680px;
      margin: 0 auto;
      padding: 24px 18px 48px;
      color: #1f2328;
      background: #f6f8fa;
      line-height: 1.65;
    }}
    main {{
      background: white;
      border: 1px solid #d0d7de;
      border-radius: 14px;
      padding: 20px;
    }}
    a.button {{
      display: block;
      margin: 14px 0;
      padding: 13px 16px;
      border-radius: 10px;
      text-align: center;
      text-decoration: none;
      font-weight: 700;
      background: #1f6feb;
      color: white;
    }}
    code {{ overflow-wrap: anywhere; }}
    .warning {{ color: #9a6700; }}
  </style>
</head>
<body>
  <main>
    <h1>kakeibo スマホ接続設定</h1>
    <p>
      暗号化機能をスマホで使うには、最初の1回だけローカルCA証明書を
      インストールして信頼する必要があります。
    </p>
    <ol>
      <li>下のボタンから公開CA証明書をダウンロードします。</li>
      <li>iPhoneでは「設定」に表示されるダウンロード済みプロファイルをインストールします。</li>
      <li>「設定 → 一般 → 情報 → 証明書信頼設定」で Kakeibo Local CA を完全に信頼します。</li>
      <li>その後、HTTPSの家計簿を開きます。</li>
    </ol>
    <a class="button" href="/kakeibo-local-ca.cer">公開CA証明書をダウンロード</a>
    <a class="button" href="{escaped_app_url}">HTTPSで家計簿を開く</a>
    <p class="warning">
      共有してよいのはこの公開CA証明書だけです。Mac内の秘密鍵ファイルは共有しないでください。
    </p>
    <p>家計簿URL: <code>{escaped_app_url}</code></p>
  </main>
</body>
</html>
""".encode("utf-8")
        self._send_bytes(200, document, content_type="text/html; charset=utf-8")

    def log_message(self, format: str, *args: object) -> None:
        print(f"[certificate-server] {self.address_string()} {format % args}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serve the public kakeibo CA certificate over local HTTP"
    )
    parser.add_argument("--cert", required=True, type=Path)
    parser.add_argument("--app-url", required=True)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", default=5174, type=int)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    certificate_path = args.cert.expanduser().resolve()
    if not certificate_path.is_file():
        raise SystemExit(f"certificate not found: {certificate_path}")

    handler_type = type(
        "ConfiguredCertificateHandler",
        (CertificateHandler,),
        {
            "certificate_path": certificate_path,
            "app_url": args.app_url,
        },
    )
    server = ThreadingHTTPServer((args.host, args.port), handler_type)
    print(f"certificate bootstrap: http://{args.host}:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
