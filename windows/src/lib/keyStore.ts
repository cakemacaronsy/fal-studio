// Port of Sources/Services/KeychainStore.swift — the FAL API key lives in a
// private file under the app-data folder; the FAL_KEY environment variable
// takes priority (parity with the macOS app).

import { create } from "zustand";
import { envFalKey, readTextIfExists, removeFile, writeText } from "./platform";

const KEY_FILE = "fal_key";

interface KeyState {
  hasKey: boolean;
  setHasKey: (has: boolean) => void;
}

export const useKeyStore = create<KeyState>((set) => ({
  hasKey: false,
  setHasKey: (hasKey) => set({ hasKey }),
}));

export async function loadStoredKey(): Promise<string | null> {
  const text = (await readTextIfExists(KEY_FILE))?.trim();
  return text ? text : null;
}

export async function saveKey(key: string): Promise<void> {
  const trimmed = key.trim();
  if (!trimmed) {
    await removeFile(KEY_FILE);
    useKeyStore.getState().setHasKey((await effectiveKey()) !== null);
    return;
  }
  await writeText(KEY_FILE, trimmed);
  useKeyStore.getState().setHasKey(true);
}

/** The key to use for API calls: FAL_KEY env var → saved key file. */
export async function effectiveKey(): Promise<string | null> {
  const env = await envFalKey();
  if (env) return env;
  return loadStoredKey();
}

export async function refreshKeyState(): Promise<void> {
  useKeyStore.getState().setHasKey((await effectiveKey()) !== null);
}
