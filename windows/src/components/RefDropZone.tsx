// Port of Sources/Views/ControlPanel/ReferenceImageDropZone.swift — unified,
// always-optional reference-image zone. The user just adds images; the model
// family resolves the endpoint automatically and the caption shows the mode.
// An end-frame slot appears when the family supports it.

import { DragEvent, useRef, useState } from "react";
import {
  RefImage,
  maxRefImages,
  supportsEndFrame,
  useDraft,
  variantCaption,
} from "../lib/draft";
import { useSettings } from "../lib/settings";
import { tr } from "../lib/lang";
import AnnotationEditor from "./AnnotationEditor";

function imageFiles(e: DragEvent): File[] {
  return Array.from(e.dataTransfer?.files ?? []).filter((f) =>
    f.type.startsWith("image/")
  );
}

export default function RefDropZone() {
  useSettings((s) => s.lang);
  const draft = useDraft();
  const [isTargeted, setTargeted] = useState(false);
  const [isEndTargeted, setEndTargeted] = useState(false);
  const [markingRef, setMarkingRef] = useState<RefImage | null>(null);
  const importInput = useRef<HTMLInputElement>(null);
  const endImportInput = useRef<HTMLInputElement>(null);

  const max = maxRefImages(draft);
  const caption = variantCaption(draft);

  return (
    <div className="card">
      <div className="section-label">
        <span>
          {tr("Reference images (optional)", "參考圖(選填)")} {draft.refImages.length}/{max}
        </span>
        {caption && <span className="variant-caption">{caption}</span>}
      </div>

      {draft.refImages.length > 0 && (
        <div className="ref-strip">
          {draft.refImages.map((ref) => (
            <div className="ref-thumb" key={ref.id}>
              <img src={ref.previewURL} alt="" />
              <button
                className="thumb-btn remove"
                onClick={() => draft.removeRefImage(ref.id)}
              >
                ✕
              </button>
              <button
                className={`thumb-btn mark${ref.annotated ? " annotated" : ""}`}
                title={tr(
                  "Mark up: draw arrows, circles or text to guide the edit",
                  "標記:畫箭頭、圈選或文字來指示修改位置"
                )}
                onClick={() => setMarkingRef(ref)}
              >
                ✎
              </button>
            </div>
          ))}
        </div>
      )}

      {draft.refImages.length < max && (
        <div
          className={`drop-target${isTargeted ? " targeted" : ""}`}
          style={{ height: draft.refImages.length === 0 ? 76 : 44, marginTop: 8 }}
          onClick={() => importInput.current?.click()}
          onDragOver={(e) => {
            e.preventDefault();
            setTargeted(true);
          }}
          onDragLeave={() => setTargeted(false)}
          onDrop={(e) => {
            e.preventDefault();
            setTargeted(false);
            const files = imageFiles(e);
            if (files.length > 0) void draft.addRefImages(files);
          }}
        >
          ⊕{" "}
          {draft.refImages.length === 0
            ? tr("Drop images here — or none for pure text mode", "拖放圖片到這裡(不放則為純文字生成)")
            : tr("Drop more", "可再拖入")}
        </div>
      )}

      {supportsEndFrame(draft) && draft.refImages.length > 0 && (
        <div className="end-frame-row" style={{ marginTop: 8 }}>
          <div className="end-frame-slot">
            {draft.endImage ? (
              <>
                <img src={draft.endImage.previewURL} alt="" />
                <button
                  className="thumb-btn remove"
                  style={{ position: "absolute", top: 3, right: 3 }}
                  onClick={() => void draft.setEndImage(null)}
                >
                  ✕
                </button>
              </>
            ) : (
              <div
                className={`drop-target${isEndTargeted ? " targeted" : ""}`}
                onClick={() => endImportInput.current?.click()}
                onDragOver={(e) => {
                  e.preventDefault();
                  setEndTargeted(true);
                }}
                onDragLeave={() => setEndTargeted(false)}
                onDrop={(e) => {
                  e.preventDefault();
                  setEndTargeted(false);
                  const files = imageFiles(e);
                  if (files.length > 0) void draft.setEndImage(files[0]);
                }}
              >
                ⊕
              </div>
            )}
          </div>
          <span className="faint" style={{ fontSize: 11 }}>
            {tr("End frame (optional)", "結尾畫格(選填)")}
          </span>
        </div>
      )}

      <input
        ref={importInput}
        type="file"
        accept="image/*"
        multiple={max > 1}
        hidden
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          if (files.length > 0) void draft.addRefImages(files);
          e.target.value = "";
        }}
      />
      <input
        ref={endImportInput}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void draft.setEndImage(file);
          e.target.value = "";
        }}
      />

      {markingRef && (
        <AnnotationEditor
          imageURL={markingRef.previewURL}
          onApply={(encoded) => draft.applyAnnotation(encoded, markingRef.id)}
          onClose={() => setMarkingRef(null)}
        />
      )}
    </div>
  );
}
