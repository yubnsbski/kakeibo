import { useState } from "react";
import "./App.css";
import { UploadView } from "./components/UploadView";
import { CryptoGate } from "./crypto/ui/CryptoGate";
import { TaxAwareEncryptedTxView } from "./crypto/ui/TaxAwareEncryptedTxView";
import { EncryptedSummaryView } from "./crypto/ui/EncryptedSummaryView";
import { EncryptedGraphView } from "./crypto/ui/EncryptedGraphView";
import { TutorialVideoButton } from "./crypto/ui/TutorialVideoButton";
import "./crypto/crypto-ui.css";

type Tab = "upload" | "list" | "summary" | "graph";

export default function App() {
  const [tab, setTab] = useState<Tab>("upload");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <CryptoGate>
      <div className="app">
        <header className="app-header">
          <h1>家計簿</h1>
          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <TutorialVideoButton />
            <nav className="tabs">
              <button
                className={tab === "upload" ? "active" : ""}
                onClick={() => setTab("upload")}
              >
                取込
              </button>
              <button
                className={tab === "list" ? "active" : ""}
                onClick={() => setTab("list")}
              >
                一覧
              </button>
              <button
                className={tab === "summary" ? "active" : ""}
                onClick={() => setTab("summary")}
              >
                集計
              </button>
              <button
                className={tab === "graph" ? "active" : ""}
                onClick={() => setTab("graph")}
              >
                グラフ
              </button>
            </nav>
          </div>
        </header>

        <main>
          {tab === "upload" && (
            <UploadView
              onUploaded={() => {
                setRefreshKey((key) => key + 1);
                setTab("list");
              }}
            />
          )}

          {tab === "list" && (
            <TaxAwareEncryptedTxView refreshKey={refreshKey} />
          )}
          {tab === "summary" && (
            <EncryptedSummaryView refreshKey={refreshKey} />
          )}
          {tab === "graph" && <EncryptedGraphView refreshKey={refreshKey} />}
        </main>
      </div>
    </CryptoGate>
  );
}
