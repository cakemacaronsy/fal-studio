import { useEffect, useState } from "react";
import ControlPanel from "./components/ControlPanel";
import Gallery from "./components/Gallery";
import SettingsModal from "./components/SettingsModal";
import { initLibrary } from "./lib/library";
import { refreshKeyState } from "./lib/keyStore";
import { checkOnLaunch, openRemoteUpdate, useUpdater } from "./lib/updater";
import { useSettings } from "./lib/settings";
import { tr } from "./lib/lang";

export default function App() {
  useSettings((s) => s.lang); // re-render the shell on language switch
  const availability = useUpdater((s) => s.availability);
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    void initLibrary();
    void refreshKeyState();
    void checkOnLaunch();
  }, []);

  return (
    <div className="app">
      <aside className="control-panel">
        <ControlPanel />
      </aside>
      <main className="gallery-area">
        <div className="top-bar">
          <div className="spacer" />
          {availability.state === "remoteRelease" && (
            <button
              className="update-button"
              onClick={openRemoteUpdate}
              title={tr("Download the new release", "下載新版本")}
            >
              ⬇︎ {tr(`Update ${availability.tag}`, `更新 ${availability.tag}`)}
            </button>
          )}
          <button
            className="icon-button"
            onClick={() => setSettingsOpen(true)}
            title={tr("Settings", "設定")}
          >
            ⚙︎
          </button>
        </div>
        <Gallery />
      </main>
      {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}
    </div>
  );
}
