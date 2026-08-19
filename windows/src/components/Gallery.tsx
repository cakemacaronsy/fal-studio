// Port of Sources/Views/Gallery/GalleryView.swift — the gallery wall (作品牆):
// this session's works up top, older works grouped in a collapsible "Past
// generations" section, with media-type filter tabs.

import { useEffect, useState } from "react";
import { GalleryItem } from "../lib/types";
import { sortedItems, useLibrary } from "../lib/library";
import { useSettings } from "../lib/settings";
import { tr } from "../lib/lang";
import GalleryCard from "./GalleryCard";
import ItemDetailSheet from "./ItemDetailSheet";

type MediaFilter = "all" | "images" | "videos";

function filterTitle(filter: MediaFilter): string {
  switch (filter) {
    case "all": return tr("All", "全部");
    case "images": return tr("Images", "圖片");
    case "videos": return tr("Videos", "影片");
  }
}

function matches(filter: MediaFilter, item: GalleryItem): boolean {
  if (filter === "all") return true;
  return filter === "images" ? item.kind === "image" : item.kind === "video";
}

export default function Gallery() {
  useSettings((s) => s.lang);
  const items = useLibrary((s) => s.items);
  const launchedAt = useLibrary((s) => s.launchedAt);
  const loaded = useLibrary((s) => s.loaded);
  const [selectedID, setSelectedID] = useState<string | null>(null);
  const [showPast, setShowPast] = useState(false);
  const [appliedInitialExpand, setAppliedInitialExpand] = useState(false);
  const [mediaFilter, setMediaFilter] = useState<MediaFilter>("all");

  const sorted = sortedItems(items);
  const currentItems = sorted.filter(
    (i) => i.createdAt >= launchedAt && matches(mediaFilter, i)
  );
  const pastItems = sorted.filter(
    (i) => i.createdAt < launchedAt && matches(mediaFilter, i)
  );

  // Nothing new yet on launch → open the past section so the wall isn't a
  // lone collapsed row.
  useEffect(() => {
    if (loaded && !appliedInitialExpand) {
      setAppliedInitialExpand(true);
      setShowPast(currentItems.length === 0);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loaded]);

  const selectedItem = items.find((i) => i.id === selectedID) ?? null;

  if (items.length === 0) {
    return (
      <div className="empty-state">
        <div className="big-icon">🖼</div>
        <div style={{ fontSize: 17, fontWeight: 500 }}>
          {tr("Your gallery wall is empty", "作品牆還是空的")}
        </div>
        <div className="faint">
          {tr(
            "Describe something on the left and press Generate.",
            "在左邊描述想生成的內容,然後按「生成」。"
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="gallery-scroll">
      <div className="filter-tabs">
        {(["all", "images", "videos"] as MediaFilter[]).map((filter) => (
          <button
            key={filter}
            className={`chip${mediaFilter === filter ? " on" : ""}`}
            onClick={() => setMediaFilter(filter)}
          >
            {filterTitle(filter)}
          </button>
        ))}
      </div>

      {currentItems.length === 0 && pastItems.length === 0 && (
        <div className="faint" style={{ textAlign: "center", paddingTop: 40 }}>
          {tr(
            `No ${filterTitle(mediaFilter).toLowerCase()} yet.`,
            `還沒有${filterTitle(mediaFilter)}作品。`
          )}
        </div>
      )}

      {currentItems.length > 0 && (
        <>
          <div className="gallery-section-header">
            {tr("This session", "本次生成")}
            <span className="count-badge">{currentItems.length}</span>
          </div>
          <div className="gallery-grid">
            {currentItems.map((item) => (
              <GalleryCard
                key={item.id}
                item={item}
                onSelect={() => {
                  if (item.status.state === "completed") setSelectedID(item.id);
                }}
              />
            ))}
          </div>
        </>
      )}

      {pastItems.length > 0 && (
        <>
          <button className="past-toggle" onClick={() => setShowPast((s) => !s)}>
            <span>{showPast ? "▾" : "▸"}</span>
            {tr("Past generations", "過往作品")}
            <span className="count-badge">{pastItems.length}</span>
          </button>
          {showPast && (
            <div className="gallery-grid">
              {[...pastItems].reverse().map((item) => (
                <GalleryCard
                  key={item.id}
                  item={item}
                  onSelect={() => {
                    if (item.status.state === "completed") setSelectedID(item.id);
                  }}
                />
              ))}
            </div>
          )}
        </>
      )}

      {selectedItem && (
        <ItemDetailSheet item={selectedItem} onClose={() => setSelectedID(null)} />
      )}
    </div>
  );
}
