// Port of Sources/Views/SettingsView.swift (General tab) — language, FAL key,
// improve-prompt LLM, updates, and mock mode.

import { useEffect, useState } from "react";
import { useSettings } from "../lib/settings";
import { loadStoredKey, saveKey } from "../lib/keyStore";
import { checkForUpdates, openRemoteUpdate, useUpdater } from "../lib/updater";
import { defaultImproveLLM } from "../lib/improver";
import { tr } from "../lib/lang";

export default function SettingsModal({ onClose }: { onClose: () => void }) {
  const settings = useSettings();
  const updater = useUpdater();
  const [apiKey, setApiKey] = useState("");
  const [saveConfirmed, setSaveConfirmed] = useState(false);

  useEffect(() => {
    void loadStoredKey().then((key) => setApiKey(key ?? ""));
  }, []);

  const save = () => {
    void saveKey(apiKey).then(() => {
      setSaveConfirmed(true);
      setTimeout(() => setSaveConfirmed(false), 2000);
    });
  };

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal settings-modal">
        <div className="detail-meta-header">
          <span>{tr("Settings", "設定")}</span>
          <button className="icon-button" onClick={onClose}>
            ✕
          </button>
        </div>
        <div className="settings-body">
          <div className="settings-section">
            <h3>{tr("Language", "語言")}</h3>
            <select
              className="model-select"
              value={settings.lang}
              onChange={(e) => settings.setLang(e.target.value as "en" | "zh-Hant")}
            >
              <option value="en">English</option>
              <option value="zh-Hant">繁體中文</option>
            </select>
          </div>

          <div className="settings-section">
            <h3>{tr("FAL API Key", "FAL API 金鑰")}</h3>
            <div className="settings-row">
              <input
                className="text-input grow"
                type="password"
                placeholder="key_id:key_secret"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && save()}
              />
              <button className="plain-button" onClick={save}>
                {tr("Save", "儲存")}
              </button>
              {saveConfirmed && (
                <span style={{ color: "var(--success)", fontSize: 12.5 }}>
                  ✓ {tr("Saved", "已儲存")}
                </span>
              )}
            </div>
            <div className="hint">
              {tr(
                "Stored in a private file only your account can read. Get a key at fal.ai → Dashboard → Keys.",
                "儲存在僅你的帳號可讀的私有檔案。金鑰請到 fal.ai → Dashboard → Keys 取得。"
              )}
            </div>
          </div>

          <div className="settings-section">
            <h3>{tr("Improve-prompt LLM", "提示詞優化模型")}</h3>
            <input
              className="text-input"
              placeholder={defaultImproveLLM}
              value={settings.improveModel}
              onChange={(e) => settings.setImproveModel(e.target.value)}
              spellCheck={false}
            />
            <div className="hint">
              {tr(
                "Any model id from fal's openrouter/router (billed to your FAL key). DeepSeek is the cheap default.",
                "可填 fal openrouter/router 支援的任一模型 id(用你的 FAL 金鑰計費)。預設為便宜的 DeepSeek。"
              )}
            </div>
          </div>

          <div className="settings-section">
            <h3>{tr("Updates", "更新")}</h3>
            <div className="detail-row">
              <span className="k">{tr("Version", "版本")}</span>
              <span className="v">{updater.currentVersion}</span>
            </div>
            <input
              className="text-input"
              placeholder="owner/repo"
              value={settings.updateRepo}
              onChange={(e) => settings.setUpdateRepo(e.target.value)}
              spellCheck={false}
            />
            <div className="settings-row">
              <button className="plain-button" onClick={() => void checkForUpdates()}>
                {tr("Check for updates", "檢查更新")}
              </button>
              {updater.isChecking && <span className="spinner small" />}
              {!updater.isChecking && updater.availability.state === "upToDate" && (
                <span style={{ color: "var(--success)", fontSize: 12.5 }}>
                  ✓ {tr("Up to date", "已是最新")}
                </span>
              )}
              {!updater.isChecking && updater.availability.state === "remoteRelease" && (
                <button
                  className="plain-button"
                  style={{ background: "var(--accent)", color: "#fff" }}
                  onClick={openRemoteUpdate}
                >
                  {tr(
                    `Download ${updater.availability.tag}`,
                    `下載 ${updater.availability.tag}`
                  )}
                </button>
              )}
            </div>
            {updater.lastError && <div className="error-text">{updater.lastError}</div>}
            <div className="hint">
              {tr(
                "Checks GitHub Releases for a newer Windows installer.",
                "檢查 GitHub Releases 是否有較新的 Windows 安裝檔。"
              )}
            </div>
          </div>

          <div className="settings-section">
            <div className="settings-row">
              <h3 className="grow">{tr("Mock mode", "模擬模式")}</h3>
              <button
                className={`switch${settings.mockMode ? " on" : ""}`}
                onClick={() => settings.setMockMode(!settings.mockMode)}
                aria-label={tr("Mock mode", "模擬模式")}
              />
            </div>
            <div className="hint">
              {tr(
                "Generates local placeholders instead of calling FAL. No credits are used.",
                "以本機占位圖代替呼叫 FAL,不會消耗任何額度。"
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
