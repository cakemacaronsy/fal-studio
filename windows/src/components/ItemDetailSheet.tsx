// Port of Sources/Views/Gallery/ItemDetailSheet.swift — enlarged preview of a
// finished work with the prompt and every setting used.

import { useEffect, useState } from "react";
import { GalleryItem, displayString } from "../lib/types";
import { specFor } from "../lib/catalog";
import { downloadToDownloads, mediaURL } from "../lib/library";
import { useDraft } from "../lib/draft";
import { useSettings } from "../lib/settings";
import { tr } from "../lib/lang";

export default function ItemDetailSheet({
  item,
  onClose,
}: {
  item: GalleryItem;
  onClose: () => void;
}) {
  useSettings((s) => s.lang);
  const draft = useDraft();
  const [url, setURL] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void mediaURL(item).then((u) => {
      if (!cancelled) setURL(u);
    });
    return () => {
      cancelled = true;
    };
  }, [item.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const spec = specFor(item.modelID);
  const paramLabel = (key: string): string =>
    spec?.parameters.find((p) => p.key === key)?.label ?? key.replaceAll("_", " ");

  const sortedParams = Object.entries(item.parameters).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  const refCount = item.refFileNames.length + (item.endRefFileName ? 1 : 0);

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal detail-sheet">
        <div className="detail-media">
          {url ? (
            item.kind === "video" ? (
              <video src={url} controls autoPlay loop />
            ) : (
              <img src={url} alt="" />
            )
          ) : (
            <span className="muted">{tr("Media file missing", "找不到媒體檔案")}</span>
          )}
        </div>
        <div className="detail-meta">
          <div className="detail-meta-header">
            <span>{item.kind === "video" ? tr("Video", "影片") : tr("Image", "圖片")}</span>
            <button className="icon-button" onClick={onClose}>
              ✕
            </button>
          </div>
          <div className="detail-meta-body">
            <div>
              <div className="detail-section-title">{tr("Prompt", "提示詞")}</div>
              <div className="prompt-text">{item.prompt}</div>
            </div>
            <div>
              <div className="detail-section-title">{tr("Model", "模型")}</div>
              <div style={{ fontSize: 13 }}>{spec?.displayName ?? item.modelID}</div>
              <div className="faint" style={{ fontSize: 10.5 }}>
                {item.endpoint}
              </div>
            </div>
            <div>
              <div className="detail-section-title">{tr("Settings", "設定")}</div>
              {sortedParams.map(([key, value]) => (
                <div className="detail-row" key={key}>
                  <span className="k">{paramLabel(key)}</span>
                  <span className="v">{displayString(value)}</span>
                </div>
              ))}
              {refCount > 0 && (
                <div className="detail-row">
                  <span className="k">{tr("Reference images", "參考圖")}</span>
                  <span className="v">{refCount}</span>
                </div>
              )}
            </div>
            <div>
              <div className="detail-section-title">{tr("Generation", "生成資訊")}</div>
              <div className="detail-row">
                <span className="k">{tr("Estimated cost", "預估費用")}</span>
                <span className="v">~${item.costEstimate.toFixed(2)}</span>
              </div>
              <div className="detail-row">
                <span className="k">{tr("Created", "建立時間")}</span>
                <span className="v">
                  {new Date(item.createdAt).toLocaleString(undefined, {
                    dateStyle: "medium",
                    timeStyle: "short",
                  })}
                </span>
              </div>
              {item.requestID && (
                <div className="detail-row">
                  <span className="k">{tr("Request", "請求編號")}</span>
                  <span className="v">{item.requestID.slice(0, 18)}</span>
                </div>
              )}
            </div>
          </div>
          <div className="detail-actions">
            {item.kind === "image" && (
              <button
                className="wide-button primary"
                onClick={() => {
                  void draft.makeVideoFrom(item);
                  onClose();
                }}
              >
                🎬 {tr("Make video from this image", "一鍵轉成影片")}
              </button>
            )}
            <button
              className="wide-button"
              onClick={() => {
                void draft.loadItem(item);
                onClose();
              }}
            >
              ↺ {tr("Reuse prompt & settings", "重用提示詞與設定")}
            </button>
            <button
              className="wide-button"
              onClick={() => {
                void downloadToDownloads(item)
                  .then(() => setSaved(true))
                  .catch(() => {});
              }}
            >
              {saved
                ? `✓ ${tr("Saved to Downloads", "已儲存到「下載」")}`
                : `⬇ ${tr("Download", "下載")}`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
