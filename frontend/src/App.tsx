import { useState } from "react";
import "./App.css";
import { UploadView } from "./components/UploadView";
import { ListView } from "./components/ListView";

type Tab = "upload" | "list";

export default function App() {
  const [tab, setTab] = useState<Tab>("upload");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="app">
      <header className="app-header">
        <h1>家計簿</h1>
        <nav className="tabs">
          <button className={tab === "upload" ? "active" : ""}
                  onClick={() => setTab("upload")}>画像アップロード</button>
          <button className={tab === "list" ? "active" : ""}
                  onClick={() => setTab("list")}>一覧</button>
        </nav>
      </header>
      <main>
        {tab === "upload" && (
          <UploadView onUploaded={() => {
            setRefreshKey((k) => k + 1);
            setTab("list");
          }} />
        )}
        {tab === "list" && <ListView refreshKey={refreshKey} />}
      </main>
    </div>
  );
}
