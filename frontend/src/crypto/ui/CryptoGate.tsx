/**
 * CryptoGate — アプリ全体のアンロックゲート。
 *
 * App 全体をこのコンポーネントでラップする。
 * アンロックが完了するまで、子 (アプリ本体) を表示しない。
 *
 * LAN上のIPアドレスをHTTPで開くとWeb Crypto APIを利用できないため、
 * スマホ接続ではHTTPSと信頼済みローカルCAが必要になる。
 */
import { useEffect, useState } from "react";
import {
  decryptJson,
  setKey,
  type EncryptedRecord,
  type KeyDerivationParams,
} from "../index";
import { useUnlocked } from "../useCrypto";
import { fetchCryptoConfig } from "../cryptoApi";
import { SetupPassphrase } from "./SetupPassphrase";
import { ShowRecoveryCode } from "./ShowRecoveryCode";
import { UnlockForm } from "./UnlockForm";
import { RecoverForm } from "./RecoverForm";

type GateState =
  | { phase: "loading" }
  | { phase: "error"; message: string }
  | {
      phase: "insecure-context";
      secureUrl: string;
      certificateUrl: string;
    }
  | { phase: "setup" }
  | { phase: "show-recovery"; recoveryCode: string }
  | { phase: "unlock"; params: KeyDerivationParams }
  | { phase: "recover"; params: KeyDerivationParams };

interface Props {
  children: React.ReactNode;
}

const API_BASE = "/api";
const VERIFY_SAMPLE_SIZE = 5;

export type KeyVerifyResult =
  | { kind: "ok" }
  | { kind: "wrong_key" }
  | { kind: "partial"; ok: number; total: number }
  | { kind: "unavailable" };

async function verifyKeyAgainstData(
  key: CryptoKey,
): Promise<KeyVerifyResult> {
  let rows: Array<{ encrypted_payload: string }>;
  try {
    const res = await fetch(`${API_BASE}/encrypted-tx`);
    if (!res.ok) {
      return { kind: "unavailable" };
    }
    rows = await res.json();
  } catch {
    return { kind: "unavailable" };
  }

  if (!Array.isArray(rows) || rows.length === 0) {
    return { kind: "ok" };
  }

  const sample = rows.slice(0, VERIFY_SAMPLE_SIZE);
  let success = 0;
  for (const row of sample) {
    try {
      const record: EncryptedRecord = JSON.parse(row.encrypted_payload);
      await decryptJson(key, record);
      success += 1;
    } catch {
      // This sample could not be decrypted with the current key.
    }
  }

  if (success === 0) {
    return { kind: "wrong_key" };
  }
  if (success === sample.length) {
    return { kind: "ok" };
  }
  return { kind: "partial", ok: success, total: sample.length };
}

function secureContextLinks(): {
  secureUrl: string;
  certificateUrl: string;
} {
  const secureUrl = new URL(window.location.href);
  secureUrl.protocol = "https:";
  secureUrl.port = "5173";

  const certificateUrl = new URL(window.location.href);
  certificateUrl.protocol = "http:";
  certificateUrl.port = "5174";
  certificateUrl.pathname = "/";
  certificateUrl.search = "";
  certificateUrl.hash = "";

  return {
    secureUrl: secureUrl.toString(),
    certificateUrl: certificateUrl.toString(),
  };
}

function hasWebCrypto(): boolean {
  return window.isSecureContext && Boolean(window.crypto?.subtle);
}

const linkStyle: React.CSSProperties = {
  display: "block",
  marginTop: 10,
  padding: "11px 14px",
  borderRadius: 8,
  background: "#1f6feb",
  color: "#ffffff",
  textDecoration: "none",
  textAlign: "center",
  fontWeight: 700,
};

export function CryptoGate({ children }: Props) {
  const [state, setState] = useState<GateState>({ phase: "loading" });
  const unlocked = useUnlocked();

  useEffect(() => {
    let cancelled = false;

    if (!hasWebCrypto()) {
      const links = secureContextLinks();
      setState({ phase: "insecure-context", ...links });
      return () => {
        cancelled = true;
      };
    }

    (async () => {
      try {
        const params = await fetchCryptoConfig();
        if (cancelled) return;
        if (params === null) {
          setState({ phase: "setup" });
        } else {
          setState({ phase: "unlock", params });
        }
      } catch (error) {
        if (cancelled) return;
        setState({
          phase: "error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  if (unlocked) {
    return <>{children}</>;
  }

  switch (state.phase) {
    case "loading":
      return (
        <div className="crypto-gate">
          <div className="crypto-card">
            <p>読み込み中…</p>
          </div>
        </div>
      );

    case "insecure-context":
      return (
        <div className="crypto-gate">
          <div className="crypto-card">
            <h2>スマホ接続にはHTTPSが必要です</h2>
            <p className="crypto-error">
              現在のHTTP接続では暗号化機能を利用できないため、取引データを開きません。
            </p>
            <p className="crypto-hint">
              最初の1回だけ公開CA証明書をインストールして信頼し、その後HTTPSで開いてください。
            </p>
            <a style={linkStyle} href={state.certificateUrl}>
              証明書の設定を開く
            </a>
            <a style={linkStyle} href={state.secureUrl}>
              HTTPSで家計簿を開く
            </a>
          </div>
        </div>
      );

    case "error":
      return (
        <div className="crypto-gate">
          <div className="crypto-card">
            <h2>エラー</h2>
            <p className="crypto-error">{state.message}</p>
            <p className="crypto-hint">
              バックエンドが起動しているか、HTTPS証明書が信頼済みか確認してください。
            </p>
          </div>
        </div>
      );

    case "setup":
      return (
        <div className="crypto-gate">
          <SetupPassphrase
            onSetupComplete={(key, recoveryCode) => {
              setKey(key);
              setState({ phase: "show-recovery", recoveryCode });
            }}
          />
        </div>
      );

    case "show-recovery":
      return (
        <div className="crypto-gate">
          <ShowRecoveryCode
            recoveryCode={state.recoveryCode}
            onConfirmed={() => {
              setState({ phase: "loading" });
            }}
          />
        </div>
      );

    case "unlock":
      return (
        <div className="crypto-gate">
          <UnlockForm
            params={state.params}
            verifyKey={verifyKeyAgainstData}
            onUnlocked={(key) => setKey(key)}
            onUseRecovery={() =>
              setState({ phase: "recover", params: state.params })
            }
          />
        </div>
      );

    case "recover":
      return (
        <div className="crypto-gate">
          <RecoverForm
            params={state.params}
            verifyKey={verifyKeyAgainstData}
            onRecovered={(key) => setKey(key)}
            onBack={() =>
              setState({ phase: "unlock", params: state.params })
            }
          />
        </div>
      );
  }
}
