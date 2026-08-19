// App preferences (the macOS app's UserDefaults equivalents), persisted to
// localStorage.

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { defaultImproveLLM } from "./improver";

export type LangCode = "en" | "zh-Hant";

interface SettingsState {
  lang: LangCode;
  mockMode: boolean;
  improveModel: string;
  /** GitHub repo checked for updates ("owner/name"; blank disables). */
  updateRepo: string;
  setLang: (lang: LangCode) => void;
  setMockMode: (on: boolean) => void;
  setImproveModel: (model: string) => void;
  setUpdateRepo: (repo: string) => void;
}

export const useSettings = create<SettingsState>()(
  persist(
    (set) => ({
      lang: "en",
      mockMode: false,
      improveModel: defaultImproveLLM,
      updateRepo: "cakemacaronsy/fal-studio",
      setLang: (lang) => set({ lang }),
      setMockMode: (mockMode) => set({ mockMode }),
      setImproveModel: (improveModel) => set({ improveModel }),
      setUpdateRepo: (updateRepo) => set({ updateRepo }),
    }),
    { name: "fal-studio-settings" }
  )
);
