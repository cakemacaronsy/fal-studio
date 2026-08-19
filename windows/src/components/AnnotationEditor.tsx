// Port of Sources/Views/Components/AnnotationEditor.swift — Gemini-style
// "Mark up" editor for reference images: sketch freehand, arrows, circles,
// and place text notes in red on the image. The flattened annotated image is
// sent to the edit model.

import { PointerEvent, useEffect, useMemo, useRef, useState } from "react";
import { EncodedImage } from "../lib/imageEncoding";
import { useSettings } from "../lib/settings";
import { tr } from "../lib/lang";

type Tool = "draw" | "arrow" | "circle" | "text";

type Mark =
  | { type: "stroke"; points: { x: number; y: number }[] }
  | { type: "arrow"; from: { x: number; y: number }; to: { x: number; y: number } }
  | { type: "ellipse"; x: number; y: number; w: number; h: number }
  | { type: "note"; text: string; at: { x: number; y: number } };

const RED = "rgb(255,41,41)";
const STAGE_W = 780;
const STAGE_H = 470;

export default function AnnotationEditor({
  imageURL,
  onApply,
  onClose,
}: {
  imageURL: string;
  onApply: (encoded: EncodedImage) => void;
  onClose: () => void;
}) {
  useSettings((s) => s.lang);
  const [tool, setTool] = useState<Tool>("draw");
  const [marks, setMarks] = useState<Mark[]>([]);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [notePoint, setNotePoint] = useState<{ x: number; y: number } | null>(null);
  const [noteText, setNoteText] = useState("");
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const dragRef = useRef<{
    start: { x: number; y: number };
    points: { x: number; y: number }[];
  } | null>(null);
  const [liveMark, setLiveMark] = useState<Mark | null>(null);

  useEffect(() => {
    const img = new Image();
    img.onload = () => setNatural({ w: img.naturalWidth, h: img.naturalHeight });
    img.src = imageURL;
  }, [imageURL]);

  const fit = useMemo(() => {
    if (!natural) return { w: STAGE_W, h: STAGE_H };
    const scale = Math.min(STAGE_W / natural.w, STAGE_H / natural.h, 1_000);
    return { w: Math.round(natural.w * scale), h: Math.round(natural.h * scale) };
  }, [natural]);

  // Redraw overlay whenever marks change.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d")!;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const mark of [...marks, ...(liveMark ? [liveMark] : [])]) {
      drawMark(ctx, mark, 1);
    }
  }, [marks, liveMark, fit]);

  const localPoint = (e: PointerEvent) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const onPointerDown = (e: PointerEvent) => {
    const p = localPoint(e);
    if (tool === "text") {
      setNotePoint(p);
      return;
    }
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    dragRef.current = { start: p, points: [p] };
  };

  const onPointerMove = (e: PointerEvent) => {
    const drag = dragRef.current;
    if (!drag) return;
    const p = localPoint(e);
    drag.points.push(p);
    if (tool === "draw") {
      setLiveMark({ type: "stroke", points: [...drag.points] });
    } else if (tool === "arrow") {
      setLiveMark({ type: "arrow", from: drag.start, to: p });
    } else if (tool === "circle") {
      setLiveMark(ellipseMark(drag.start, p));
    }
  };

  const onPointerUp = (e: PointerEvent) => {
    const drag = dragRef.current;
    dragRef.current = null;
    setLiveMark(null);
    if (!drag) return;
    const p = localPoint(e);
    const dist = Math.hypot(p.x - drag.start.x, p.y - drag.start.y);
    if (tool === "draw" && drag.points.length > 1) {
      setMarks((m) => [...m, { type: "stroke", points: drag.points }]);
    } else if (tool === "arrow" && dist > 8) {
      setMarks((m) => [...m, { type: "arrow", from: drag.start, to: p }]);
    } else if (tool === "circle" && dist > 8) {
      setMarks((m) => [...m, ellipseMark(drag.start, p)]);
    }
  };

  const addNote = () => {
    if (notePoint && noteText.trim()) {
      setMarks((m) => [...m, { type: "note", text: noteText, at: notePoint }]);
    }
    setNoteText("");
    setNotePoint(null);
  };

  // Flatten: render the original image at natural size with marks scaled up.
  const apply = async () => {
    if (!natural) return;
    const scale = natural.w / fit.w;
    const canvas = document.createElement("canvas");
    canvas.width = natural.w;
    canvas.height = natural.h;
    const ctx = canvas.getContext("2d")!;
    const img = new Image();
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error("image load failed"));
      img.src = imageURL;
    });
    ctx.drawImage(img, 0, 0, natural.w, natural.h);
    for (const mark of marks) {
      drawMark(ctx, mark, scale);
    }
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", 0.92)
    );
    if (blob) {
      onApply({ bytes: new Uint8Array(await blob.arrayBuffer()), mime: "image/jpeg" });
    }
    onClose();
  };

  const toolButton = (t: Tool, icon: string, help: string) => (
    <button
      className={`tool-btn${tool === t ? " selected" : ""}`}
      title={help}
      onClick={() => setTool(t)}
    >
      {icon}
    </button>
  );

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal annotation-modal">
        <div className="annotation-toolbar">
          {toolButton("draw", "✏️", tr("Sketch", "手繪"))}
          {toolButton("arrow", "↗", tr("Arrow", "箭頭"))}
          {toolButton("circle", "◯", tr("Circle", "圈選"))}
          {toolButton("text", "T", tr("Text note", "文字"))}
          <span style={{ width: 1, height: 18, background: "var(--border)" }} />
          <button
            className="tool-btn"
            disabled={marks.length === 0}
            title={tr("Undo", "復原")}
            onClick={() => setMarks((m) => m.slice(0, -1))}
          >
            ↩
          </button>
          <button
            className="tool-btn"
            disabled={marks.length === 0}
            title={tr("Clear all markings", "清除全部標記")}
            onClick={() => setMarks([])}
          >
            🗑
          </button>
          <div style={{ flex: 1 }} />
          <strong>{tr("Mark up", "標記模式")}</strong>
        </div>
        <div className="annotation-stage">
          <div className="annotation-canvas-wrap" style={{ width: fit.w, height: fit.h }}>
            <img src={imageURL} width={fit.w} height={fit.h} alt="" />
            <canvas
              ref={canvasRef}
              width={fit.w}
              height={fit.h}
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={onPointerUp}
            />
            {notePoint && (
              <div
                className="note-input-overlay"
                style={{
                  left: Math.min(notePoint.x, fit.w - 240),
                  top: Math.min(notePoint.y, fit.h - 44),
                }}
              >
                <input
                  className="text-input"
                  style={{ width: 170 }}
                  autoFocus
                  placeholder={tr("e.g. change this to red", "例如:把這裡改成紅色")}
                  value={noteText}
                  onChange={(e) => setNoteText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") addNote();
                    if (e.key === "Escape") {
                      setNoteText("");
                      setNotePoint(null);
                    }
                  }}
                />
                <button className="plain-button" onClick={addNote}>
                  {tr("Add", "加入")}
                </button>
              </div>
            )}
          </div>
        </div>
        <div className="annotation-footer">
          <span className="faint" style={{ fontSize: 12 }}>
            {tr(
              "Mark what to change — the model follows your red markings.",
              "標記想修改的地方——模型會依照紅色記號執行。"
            )}
          </span>
          <div style={{ flex: 1 }} />
          <button className="plain-button" onClick={onClose}>
            {tr("Cancel", "取消")}
          </button>
          <button
            className="plain-button"
            style={{ background: "var(--accent)", color: "#fff" }}
            disabled={marks.length === 0}
            onClick={() => void apply()}
          >
            {tr("Apply markup", "套用標記")}
          </button>
        </div>
      </div>
    </div>
  );
}

function ellipseMark(a: { x: number; y: number }, b: { x: number; y: number }): Mark {
  return {
    type: "ellipse",
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    w: Math.abs(a.x - b.x),
    h: Math.abs(a.y - b.y),
  };
}

function drawMark(ctx: CanvasRenderingContext2D, mark: Mark, scale: number): void {
  ctx.strokeStyle = RED;
  ctx.fillStyle = RED;
  ctx.lineWidth = 3 * scale;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  switch (mark.type) {
    case "stroke": {
      if (mark.points.length < 2) return;
      ctx.beginPath();
      ctx.moveTo(mark.points[0].x * scale, mark.points[0].y * scale);
      for (const p of mark.points.slice(1)) {
        ctx.lineTo(p.x * scale, p.y * scale);
      }
      ctx.stroke();
      break;
    }
    case "arrow": {
      const from = { x: mark.from.x * scale, y: mark.from.y * scale };
      const to = { x: mark.to.x * scale, y: mark.to.y * scale };
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      const angle = Math.atan2(to.y - from.y, to.x - from.x);
      const spread = Math.PI / 7;
      const len = 12 * scale;
      for (const headAngle of [angle + Math.PI - spread, angle + Math.PI + spread]) {
        ctx.moveTo(to.x, to.y);
        ctx.lineTo(to.x + Math.cos(headAngle) * len, to.y + Math.sin(headAngle) * len);
      }
      ctx.stroke();
      break;
    }
    case "ellipse": {
      ctx.beginPath();
      ctx.ellipse(
        (mark.x + mark.w / 2) * scale,
        (mark.y + mark.h / 2) * scale,
        (mark.w / 2) * scale,
        (mark.h / 2) * scale,
        0,
        0,
        Math.PI * 2
      );
      ctx.stroke();
      break;
    }
    case "note": {
      ctx.font = `bold ${15 * scale}px system-ui, sans-serif`;
      ctx.textBaseline = "top";
      ctx.fillText(mark.text, mark.at.x * scale, mark.at.y * scale);
      break;
    }
  }
}
