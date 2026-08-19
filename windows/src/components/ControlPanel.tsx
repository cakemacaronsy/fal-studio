// Port of Sources/Views/ControlPanel/ControlPanelView.swift — mode tabs,
// family picker, reference-image zone, prompt editor with ✨ Improve,
// parameter chips, and the generate bar.

import { useState } from "react";
import { MediaKind, ParameterSpec, boolValue, intValue, stringValue } from "../lib/types";
import { families } from "../lib/catalog";
import {
  draftEstimatedCost,
  draftSpec,
  hasAnnotatedRefs,
  maxRefImages,
  useDraft,
} from "../lib/draft";
import { improvePrompt, startGeneration, useGeneration } from "../lib/generation";
import { useSettings } from "../lib/settings";
import { useKeyStore } from "../lib/keyStore";
import { tr, trParam } from "../lib/lang";
import ChipMenu, { AspectGlyph } from "./ChipMenu";
import RefDropZone from "./RefDropZone";

export default function ControlPanel() {
  useSettings((s) => s.lang);
  const draft = useDraft();
  const spec = draftSpec(draft);

  return (
    <>
      <ModeTabBar />
      <div className="panel-body">
        <div className="card">
          <div className="section-label">{tr("Model", "模型")}</div>
          <select
            className="model-select"
            value={draft.modelID}
            onChange={(e) => draft.selectModel(e.target.value)}
          >
            {families
              .filter((f) => f.kind === draft.mode)
              .map((f) => (
                <option key={f.id} value={f.id}>
                  {f.displayName}
                </option>
              ))}
          </select>
        </div>

        {maxRefImages(draft) > 0 && <RefDropZone />}

        <PromptEditor />

        <div className="card">
          <div className="section-label">{tr("Settings", "設定")}</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
            {spec.parameters.map((param) => (
              <ParamChip key={param.key} param={param} />
            ))}
          </div>
        </div>
      </div>
      <GenerateBar />
    </>
  );
}

// MARK: - Mode tabs

function ModeTabBar() {
  const mode = useDraft((s) => s.mode);
  const selectMode = useDraft((s) => s.selectMode);
  const tab = (title: string, icon: string, kind: MediaKind) => (
    <button
      className={`mode-tab${mode === kind ? " selected" : ""}`}
      onClick={() => selectMode(kind)}
    >
      <span>{icon}</span>
      {title}
    </button>
  );
  return (
    <div className="mode-tabs">
      {tab(tr("Image", "圖片"), "🖼", "image")}
      {tab(tr("Video", "影片"), "🎞", "video")}
    </div>
  );
}

// MARK: - Prompt editor with ✨ Improve

function PromptEditor() {
  const draft = useDraft();
  const mockMode = useSettings((s) => s.mockMode);
  const hasKey = useKeyStore((s) => s.hasKey);

  const improve = async () => {
    const original = draft.prompt.trim();
    if (!original) return;
    draft.setImproving(true);
    const spec = draftSpec(useDraft.getState());
    try {
      const improved = await improvePrompt(original, spec, draft.jsonMode);
      useDraft.getState().applyImproved(improved);
      useDraft.getState().setImproving(false);
    } catch (error) {
      useDraft.getState().setImproving(
        false,
        error instanceof Error ? error.message : String(error)
      );
    }
  };

  return (
    <div className="card">
      <div className="section-label">
        <span>{tr("Prompt", "提示詞")}</span>
        <span className="improve-controls">
          <button
            className={`small-button${draft.jsonMode ? " toggled" : ""}`}
            title={tr(
              "Structured mode: use this model's official prompt template",
              "結構化模式:使用此模型官方的提示詞模板"
            )}
            onClick={() => draft.setJsonMode(!draft.jsonMode)}
          >
            {"{ }"}
          </button>
          {draft.promptBackup !== null && (
            <button
              className="small-button"
              title={tr("Revert to your original prompt", "還原原始提示詞")}
              onClick={draft.revertImproved}
            >
              ↩
            </button>
          )}
          {draft.isImproving ? (
            <span className="spinner small" />
          ) : (
            <button
              className="small-button"
              disabled={
                draft.prompt.trim().length === 0 || (!mockMode && !hasKey)
              }
              title={tr(
                "Rewrite the prompt per this model's official prompting guide",
                "依此模型官方提示詞指南優化"
              )}
              onClick={() => void improve()}
            >
              ✨ {tr("Improve", "優化")}
            </button>
          )}
        </span>
      </div>
      <textarea
        className="prompt-editor"
        placeholder={
          draft.mode === "image"
            ? tr("Describe the image you want…", "描述你想生成的圖片…")
            : tr("Describe the video you want…", "描述你想生成的影片…")
        }
        value={draft.prompt}
        onChange={(e) => draft.setPrompt(e.target.value)}
      />
      {draft.improveError && <div className="error-text">{draft.improveError}</div>}
    </div>
  );
}

// MARK: - Parameter chips

function ParamChip({ param }: { param: ParameterSpec }) {
  const draft = useDraft();
  const kind = param.kind;

  if (kind.type === "toggle") {
    const isOn = boolValue(draft.paramValues[param.key]) ?? kind.defaultValue;
    return (
      <button
        className={`chip${isOn ? " on" : ""}`}
        onClick={() => draft.setValue(param.key, !isOn)}
      >
        {trParam(param.label)} {isOn ? tr("on", "開") : tr("off", "關")}
      </button>
    );
  }

  if (kind.type === "choice") {
    const current = stringValue(draft.paramValues[param.key]) ?? kind.defaultValue;
    return (
      <ChipMenu
        label={`${trParam(param.label)} · ${current}`}
        options={kind.options}
        isSelected={(o) => o === current}
        onSelect={(o) => draft.setValue(param.key, o)}
        renderOption={
          param.key === "aspect_ratio"
            ? (o) => (
                <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
                  <AspectGlyph ratio={o} />
                  {o}
                </span>
              )
            : undefined
        }
      />
    );
  }

  const current = intValue(draft.paramValues[param.key]) ?? kind.defaultValue;
  const options = Array.from(
    { length: kind.max - kind.min + 1 },
    (_, i) => String(kind.min + i)
  );
  return (
    <ChipMenu
      label={`${trParam(param.label)} · ${current}`}
      options={options}
      isSelected={(o) => Number(o) === current}
      onSelect={(o) => draft.setValue(param.key, Number(o))}
    />
  );
}

// MARK: - Generate bar

function GenerateBar() {
  useSettings((s) => s.lang);
  const draft = useDraft();
  const mockMode = useSettings((s) => s.mockMode);
  const hasKey = useKeyStore((s) => s.hasKey);
  useGeneration((s) => s.running); // keep cost row fresh while jobs run
  const [starting, setStarting] = useState(false);

  let blockedReason: string | null = null;
  if (!mockMode && !hasKey) {
    blockedReason = tr("Add your FAL key in Settings ⚙︎", "請在設定 ⚙︎ 加入你的 FAL 金鑰");
  } else if (draft.prompt.trim().length === 0) {
    blockedReason = tr("Describe what you want to generate.", "先描述你想生成的內容。");
  } else if (draft.endImage !== null && draft.refImages.length === 0) {
    blockedReason = tr(
      "An end frame needs a start frame too.",
      "設定結尾畫格前,請先加入起始畫格。"
    );
  }

  const cost = draftEstimatedCost(draft);

  const generate = async () => {
    if (starting) return;
    setStarting(true);
    try {
      const state = useDraft.getState();
      let prompt = state.prompt.trim();
      if (hasAnnotatedRefs(state)) {
        // The reference image carries Gemini-style red markup; tell the model
        // to obey it and keep it out of the result.
        prompt +=
          "\n\nThe reference image contains red markup (arrows, circles, sketch lines, handwritten notes). Treat these markings as precise editing instructions for the marked areas. Do not include any of the red markup in the final output.";
      }
      await startGeneration(
        draftSpec(state),
        prompt,
        state.paramValues,
        state.refImages.map((r) => r.encoded.bytes),
        state.endImage?.encoded.bytes ?? null
      );
    } finally {
      setStarting(false);
    }
  };

  return (
    <div className="panel-footer">
      {mockMode && (
        <div className="mock-banner">
          ⚠️
          <span>
            {tr(
              "MOCK MODE — placeholders only, no real generation. Turn off in Settings.",
              "模擬模式 — 只會產生占位圖,不會真正生成。請到設定關閉。"
            )}
          </span>
        </div>
      )}
      {blockedReason && <div className="blocked-reason">{blockedReason}</div>}
      <div className="generate-row">
        <div>
          <div className="cost-label">{tr("Estimated cost", "預估費用")}</div>
          <div className="cost-value">{cost > 0 ? `~$${cost.toFixed(2)}` : "~$?"}</div>
        </div>
        <button
          className="generate-button"
          disabled={blockedReason !== null || starting}
          onClick={() => void generate()}
        >
          ✦ {tr("Generate", "生成")}
        </button>
      </div>
    </div>
  );
}
