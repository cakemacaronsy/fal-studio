// Port of Sources/Services/Lang.swift — in-app UI language, independent of
// the OS language. Components subscribe via useSettings so they re-render on
// switch; tr() reads the current value.

import { useSettings } from "./settings";

/** Pick the UI string for the current language: tr("Prompt", "提示詞"). */
export function tr(english: string, chinese: string): string {
  return useSettings.getState().lang === "zh-Hant" ? chinese : english;
}

/** Localize the parameter chip labels defined in the model catalog. */
export function trParam(label: string): string {
  if (useSettings.getState().lang !== "zh-Hant") return label;
  switch (label) {
    case "Aspect": return "寬高比";
    case "Resolution": return "解析度";
    case "Duration": return "長度";
    case "Audio": return "音訊";
    case "Quality": return "品質";
    case "Images": return "張數";
    default: return label;
  }
}
