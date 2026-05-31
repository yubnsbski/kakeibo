/**
 * データ分裂診断パネル。
 *
 * セキュリティレビューで判明した「誤鍵アンロックの穴」により、
 * 過去に異なるパスフレーズで保存されたデータが混在している可能性がある。
 * このパネルは、現在アンロックしている鍵で encrypted_transactions の
 * 全件を試し復号し、復号できた件数 / できなかった件数を表示する。
 *
 * - 全件成功     → データ分裂なし。健全。
 * - 一部のみ成功 → データ分裂あり。復号できない行は別の鍵で保存されている。
 *
 * 一時的な診断用途。健全性を確認したら撤去してよい。
 */
import { useState } from "react";
import { decryptJson, requireKey, type EncryptedRecord } from "../index";
import { fetchEncryptedTx } from "../encryptedTxApi";

type DiagnosisState =
  | { kind: "idle" }
  | { kind: "running" }
  | { kind: "error"; message: string }
  | {
      kind: "done";
      total: number;
      ok: number;
      failed: number;
      failedIds: number[];
    };

export function DataIntegrityCheck() {
  const [state, setState] = useState<DiagnosisState>({ kind: "idle" });

  async function runCheck() {
    setState({ kind: "running" });
    try {
      const key = requireKey();
      const rows = await fetchEncryptedTx();

      let ok = 0;
      const failedIds: number[] = [];

      for (const row of rows) {
        try {
          const record: EncryptedRecord = JSON.parse(row.encrypted_payload);
          await decryptJson(key, record);
          ok += 1;
        } catch {
          failedIds.push(row.id);
        }
      }

      setState({
        kind: "done",
        total: rows.length,
        ok,
        failed: failedIds.length,
        failedIds,
      });
    } catch (e) {
      setState({
        kind: "error",
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return (
    <div
      style={{
        border: "1px dashed #b06a00",
        borderRadius: 8,
        padding: 12,
        margin: "12px 0",
        background: "#fffaf0",
      }}
    >
      <h3 style={{ margin: "0 0 6px", fontSize: "1rem" }}>
        データ健全性チェック
      </h3>
      <p style={{ fontSize: "0.82rem", color: "#57606a", margin: "0 0 10px" }}>
        現在の鍵で全暗号化取引を試し復号し、復号できない行
        (＝異なる鍵で保存された行) が無いか確認します。
      </p>

      <button onClick={() => void runCheck()} disabled={state.kind === "running"}>
        {state.kind === "running" ? "チェック中…" : "健全性をチェック"}
      </button>

      {state.kind === "error" && (
        <p className="crypto-error" style={{ marginTop: 8 }}>
          {state.message}
        </p>
      )}

      {state.kind === "done" && (
        <div style={{ marginTop: 10, fontSize: "0.9rem" }}>
          {state.failed === 0 ? (
            <p style={{ color: "#1a7f37", fontWeight: 600 }}>
              ✓ 健全: 全{state.total}件すべて現在の鍵で復号できました。
              データ分裂はありません。
            </p>
          ) : (
            <div>
              <p style={{ color: "#cf222e", fontWeight: 600 }}>
                ⚠ データ分裂を検知: 全{state.total}件中、
                {state.ok}件は復号成功、{state.failed}件は復号失敗。
              </p>
              <p style={{ fontSize: "0.82rem", color: "#57606a" }}>
                復号できない行は、過去に別のパスフレーズで保存された
                可能性があります。失敗した取引ID:{" "}
                {state.failedIds.join(", ")}
              </p>
              <p style={{ fontSize: "0.82rem", color: "#57606a" }}>
                対処: 心当たりのある別パスフレーズがあれば、一度ロックして
                そのパスフレーズで再アンロックし、このチェックを実行すると
                どちらの鍵が何件に対応するか切り分けられます。
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
