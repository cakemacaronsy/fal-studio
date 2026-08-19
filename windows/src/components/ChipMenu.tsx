import { ReactNode, useEffect, useRef, useState } from "react";

/** Capsule chip that opens a small dropdown of options (the SwiftUI Menu
 *  equivalent used for parameter chips). */
export default function ChipMenu({
  label,
  highlighted,
  options,
  isSelected,
  onSelect,
  renderOption,
}: {
  label: string;
  highlighted?: boolean;
  options: string[];
  isSelected: (option: string) => boolean;
  onSelect: (option: string) => void;
  renderOption?: (option: string) => ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  return (
    <div className="chip-menu" ref={ref}>
      <button
        className={`chip${highlighted ? " on" : ""}`}
        onClick={() => setOpen((o) => !o)}
      >
        {label}
      </button>
      {open && (
        <div className="menu-pop">
          {options.map((option) => (
            <button
              key={option}
              className="menu-item"
              onClick={() => {
                onSelect(option);
                setOpen(false);
              }}
            >
              <span className="check">{isSelected(option) ? "✓" : ""}</span>
              {renderOption ? renderOption(option) : <span>{option}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Shape glyph showing the output orientation at a glance (AspectGlyph port). */
export function AspectGlyph({ ratio }: { ratio: string }) {
  const parts = ratio.split(":").map(Number).filter((n) => Number.isFinite(n) && n > 0);
  let width = 16;
  let height = 12;
  if (parts.length === 2) {
    const [w, h] = parts;
    if (w >= h) {
      width = 16;
      height = Math.max(6, Math.round((16 * h) / w));
    } else {
      height = 16;
      width = Math.max(6, Math.round((16 * w) / h));
    }
  }
  return <span className="aspect-glyph" style={{ width, height }} />;
}
