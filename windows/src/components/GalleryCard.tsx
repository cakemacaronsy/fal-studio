// Port of Sources/Views/Gallery/GalleryCardView.swift — one card on the
// gallery wall: thumbnail with hover actions for finished works, a spinner
// card while generating, error card on failure.

import { useEffect, useState } from "react";
import { GalleryItem } from "../lib/types";
import { deleteItem, downloadToDownloads, mediaURL, thumbnailURL } from "../lib/library";
import { cancelGeneration, retryGeneration, useGeneration } from "../lib/generation";
import { useDraft } from "../lib/draft";
import { useSettings } from "../lib/settings";
import { tr } from "../lib/lang";

export default function GalleryCard({
  item,
  onSelect,
}: {
  item: GalleryItem;
  onSelect: () => void;
}) {
  useSettings((s) => s.lang);
  const [confirmDelete, setConfirmDelete] = useState(false);

  return (
    <div className="gallery-card">
      {item.status.state === "generating" && <GeneratingCard item={item} />}
      {item.status.state === "failed" && (
        <FailedCard
          item={item}
          message={item.status.message}
          onDelete={() => setConfirmDelete(true)}
        />
      )}
      {item.status.state === "completed" && (
        <CompletedCard item={item} onSelect={onSelect} onDelete={() => setConfirmDelete(true)} />
      )}
      {confirmDelete && (
        <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && setConfirmDelete(false)}>
          <div className="modal confirm-box">
            <strong>{tr("Delete this work?", "刪除這件作品?")}</strong>
            <span className="muted" style={{ fontSize: 12.5 }}>
              {tr(
                "The file is removed from your gallery. This can't be undone.",
                "檔案將從作品牆移除,無法復原。"
              )}
            </span>
            <div className="confirm-actions">
              <button className="plain-button" onClick={() => setConfirmDelete(false)}>
                {tr("Cancel", "取消")}
              </button>
              <button
                className="plain-button destructive"
                onClick={() => {
                  setConfirmDelete(false);
                  void deleteItem(item);
                }}
              >
                {tr("Delete", "刪除")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// MARK: Completed

function CompletedCard({
  item,
  onSelect,
  onDelete,
}: {
  item: GalleryItem;
  onSelect: () => void;
  onDelete: () => void;
}) {
  const draft = useDraft();
  const [thumb, setThumb] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const url =
        (await thumbnailURL(item)) ??
        (item.kind === "image" ? await mediaURL(item) : null);
      if (!cancelled) setThumb(url);
    })();
    return () => {
      cancelled = true;
    };
  }, [item.thumbnailFileName, item.fileName, item.kind]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <>
      {thumb ? (
        <img className="thumb" src={thumb} alt="" onClick={onSelect} />
      ) : (
        <div
          className="card-center"
          style={{ cursor: "pointer", background: "var(--bg-fill)" }}
          onClick={onSelect}
        >
          {item.kind === "video" ? <span style={{ fontSize: 28 }}>🎞</span> : <span className="spinner" />}
        </div>
      )}
      {item.kind === "video" && <div className="video-badge">▶</div>}
      <div className="card-overlay">
        {item.kind === "image" && (
          <>
            <button
              className="overlay-btn"
              title={tr("Make video from this image", "一鍵轉成影片")}
              onClick={() => void draft.makeVideoFrom(item)}
            >
              🎬
            </button>
            <button
              className="overlay-btn"
              title={tr("Use as reference image", "作為參考圖")}
              onClick={() => void draft.useAsReference(item)}
            >
              🖇
            </button>
          </>
        )}
        <button
          className="overlay-btn"
          title={saved ? tr("Saved", "已儲存") : tr("Save to Downloads", "儲存到「下載」")}
          onClick={() => {
            void downloadToDownloads(item)
              .then(() => setSaved(true))
              .catch(() => {});
          }}
        >
          {saved ? "✓" : "⬇"}
        </button>
        <button className="overlay-btn" title={tr("Delete", "刪除")} onClick={onDelete}>
          🗑
        </button>
      </div>
    </>
  );
}

// MARK: Generating

function GeneratingCard({ item }: { item: GalleryItem }) {
  const status = useGeneration((s) => s.liveStatus[item.id]);
  const [, forceTick] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => forceTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const elapsed = Math.max(
    0,
    Math.floor((Date.now() - new Date(item.createdAt).getTime()) / 1000)
  );

  let statusLine: string;
  switch (status) {
    case "IN_QUEUE": statusLine = "queued"; break;
    case "IN_PROGRESS": statusLine = "in progress"; break;
    case "DOWNLOADING": statusLine = "downloading"; break;
    case "GENERATING":
    case undefined: statusLine = "working"; break;
    default: statusLine = status.toLowerCase();
  }

  return (
    <>
      <div className="card-center">
        <span className="spinner" />
        <span className="muted" style={{ fontWeight: 500 }}>
          {tr("Generating…", "生成中…")}
        </span>
        <span className="status-line">
          {statusLine} · {elapsed}s
        </span>
      </div>
      <div className="card-overlay">
        <button
          className="overlay-btn"
          title={tr("Cancel", "取消")}
          onClick={() => cancelGeneration(item.id)}
        >
          ✕
        </button>
      </div>
    </>
  );
}

// MARK: Failed

function FailedCard({
  item,
  message,
  onDelete,
}: {
  item: GalleryItem;
  message: string;
  onDelete: () => void;
}) {
  return (
    <div className="card-center">
      <span style={{ fontSize: 20 }}>⚠️</span>
      <span
        className="muted"
        style={{
          fontSize: 11.5,
          display: "-webkit-box",
          WebkitLineClamp: 3,
          WebkitBoxOrient: "vertical",
          overflow: "hidden",
        }}
      >
        {message}
      </span>
      <div style={{ display: "flex", gap: 10 }}>
        <button
          className="plain-button"
          style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => {
            void retryGeneration(item).then(() => deleteItem(item));
          }}
        >
          {tr("Retry", "重試")}
        </button>
        <button
          className="plain-button destructive"
          style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={onDelete}
        >
          {tr("Delete", "刪除")}
        </button>
      </div>
    </div>
  );
}
