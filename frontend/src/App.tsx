import { useState } from "react";
import "./App.css";
import { UploadView } from "./components/UploadView";
import { ListView } from "./components/ListView";
import { GraphView } from "./components/GraphView";

type Tab = "upload" | "list" | "graph";

export default function App() {
  const [tab, setTab] = useState<Tab>("upload");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="app">
      <header className="app-header">
        <h1>家計簿</h1>
        <nav className="tabs">
          <button className={tab === "upload" ? "active" : ""}
                  onClick={() => setTab("upload")}>取込</button>
          <button className={tab === "list" ? "active" : ""}
                  onClick={() => setTab("list")}>一覧</button>
          <button className={tab === "graph" ? "active" : ""}
                  onClick={() => setTab("graph")}>グラフ</button>
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
        {tab === "graph" && <GraphView />}
      </main>
    </div>
  );
}
