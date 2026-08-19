// Thin platform layer. Inside Tauri it uses the native plugins (fs under the
// per-app AppData dir, CORS-free http, notifications, opener). In a plain
// browser (vite dev without Tauri) it falls back to in-memory storage and
// window.fetch so the UI can be exercised with mock mode.

import { fetch as tauriFetch } from "@tauri-apps/plugin-http";
import {
  BaseDirectory,
  copyFile,
  exists,
  mkdir,
  readFile,
  readTextFile,
  remove,
  writeFile,
  writeTextFile,
} from "@tauri-apps/plugin-fs";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { appDataDir, join } from "@tauri-apps/api/path";
import { getVersion } from "@tauri-apps/api/app";
import { openUrl as tauriOpenUrl } from "@tauri-apps/plugin-opener";
import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from "@tauri-apps/plugin-notification";

export const isTauri: boolean =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

// ---- HTTP ----

/** fetch that bypasses webview CORS inside Tauri. */
export const httpFetch: typeof fetch = isTauri ? (tauriFetch as typeof fetch) : fetch;

// ---- Files (paths relative to the app-data root) ----

const memoryFS = new Map<string, Uint8Array>();
const memoryURLs = new Map<string, string>();

const appData = { baseDir: BaseDirectory.AppData };

let appDataPathPromise: Promise<string> | null = null;
function appDataPath(): Promise<string> {
  if (!appDataPathPromise) appDataPathPromise = appDataDir();
  return appDataPathPromise;
}

export async function ensureDir(rel: string): Promise<void> {
  if (!isTauri) return;
  if (!(await exists(rel, appData))) {
    await mkdir(rel, { ...appData, recursive: true });
  }
}

export async function readTextIfExists(rel: string): Promise<string | null> {
  if (!isTauri) {
    const bytes = memoryFS.get(rel);
    return bytes ? new TextDecoder().decode(bytes) : null;
  }
  try {
    if (!(await exists(rel, appData))) return null;
    return await readTextFile(rel, appData);
  } catch {
    return null;
  }
}

export async function writeText(rel: string, text: string): Promise<void> {
  if (!isTauri) {
    memoryFS.set(rel, new TextEncoder().encode(text));
    return;
  }
  await writeTextFile(rel, text, appData);
}

export async function writeBytes(rel: string, bytes: Uint8Array): Promise<void> {
  if (!isTauri) {
    memoryFS.set(rel, bytes);
    const old = memoryURLs.get(rel);
    if (old) {
      URL.revokeObjectURL(old);
      memoryURLs.delete(rel);
    }
    return;
  }
  await writeFile(rel, bytes, appData);
}

export async function readBytes(rel: string): Promise<Uint8Array | null> {
  if (!isTauri) return memoryFS.get(rel) ?? null;
  try {
    if (!(await exists(rel, appData))) return null;
    return await readFile(rel, appData);
  } catch {
    return null;
  }
}

export async function removeFile(rel: string): Promise<void> {
  if (!isTauri) {
    memoryFS.delete(rel);
    return;
  }
  try {
    if (await exists(rel, appData)) await remove(rel, appData);
  } catch {
    // best-effort cleanup, same as the macOS app
  }
}

function mimeForExtension(ext: string): string {
  switch (ext) {
    case "png": return "image/png";
    case "jpeg":
    case "jpg": return "image/jpeg";
    case "mp4": return "video/mp4";
    case "webm": return "video/webm";
    case "mov": return "video/quicktime";
    default: return "application/octet-stream";
  }
}

/** A URL the webview can load for a stored media/thumbnail/ref file. */
export async function fileDisplayURL(rel: string): Promise<string | null> {
  if (!isTauri) {
    const cached = memoryURLs.get(rel);
    if (cached) return cached;
    const bytes = memoryFS.get(rel);
    if (!bytes) return null;
    const ext = rel.split(".").pop() ?? "";
    const url = URL.createObjectURL(
      new Blob([bytes.slice().buffer], { type: mimeForExtension(ext) })
    );
    memoryURLs.set(rel, url);
    return url;
  }
  const abs = await join(await appDataPath(), rel);
  return convertFileSrc(abs);
}

/** Copy a stored file into the user's Downloads folder under `fileName`.
 *  Returns false when the name is taken (caller retries with a counter). */
export async function copyToDownloads(rel: string, fileName: string): Promise<boolean> {
  if (!isTauri) {
    // Browser fallback: trigger a normal download.
    const url = await fileDisplayURL(rel);
    if (!url) throw new Error("file missing");
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName;
    a.click();
    return true;
  }
  if (await exists(fileName, { baseDir: BaseDirectory.Download })) return false;
  await copyFile(rel, fileName, {
    fromPathBaseDir: BaseDirectory.AppData,
    toPathBaseDir: BaseDirectory.Download,
  });
  return true;
}

// ---- Notifications ----

let notifyPermissionRequested = false;

export async function notify(title: string, body: string): Promise<void> {
  if (!isTauri) {
    try {
      if (Notification.permission === "granted") new Notification(title, { body });
    } catch {
      // notifications unavailable in this browser context
    }
    return;
  }
  try {
    let granted = await isPermissionGranted();
    if (!granted && !notifyPermissionRequested) {
      notifyPermissionRequested = true;
      granted = (await requestPermission()) === "granted";
    }
    if (granted) sendNotification({ title, body });
  } catch {
    // never let a notification failure break a finished generation
  }
}

// ---- Misc ----

export async function openExternalURL(url: string): Promise<void> {
  if (!isTauri) {
    window.open(url, "_blank");
    return;
  }
  await tauriOpenUrl(url);
}

export async function appVersion(): Promise<string> {
  if (!isTauri) return "1.3.0-dev";
  return getVersion();
}

/** FAL_KEY from the process environment (parity with the macOS app). */
export async function envFalKey(): Promise<string | null> {
  if (!isTauri) return null;
  try {
    return (await invoke<string | null>("env_fal_key")) ?? null;
  } catch {
    return null;
  }
}
