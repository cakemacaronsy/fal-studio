// Port of Sources/Services/LibraryStore.swift — owns the gallery items and
// persists them (plus media/thumbnail/ref files) under the app-data folder.

import { create } from "zustand";
import { GalleryItem } from "./types";
import {
  copyToDownloads,
  ensureDir,
  fileDisplayURL,
  readBytes,
  readTextIfExists,
  removeFile,
  writeBytes,
  writeText,
} from "./platform";
import { mimeForBytes } from "./imageEncoding";

const INDEX_FILE = "library.json";

interface LibraryState {
  items: GalleryItem[];
  /** When this app session started — the gallery groups older works under
   *  "Past generations". */
  launchedAt: string;
  loaded: boolean;
  setItems: (items: GalleryItem[]) => void;
  appendItem: (item: GalleryItem) => void;
  updateItem: (item: GalleryItem) => void;
  removeItem: (id: string) => void;
}

export const useLibrary = create<LibraryState>((set) => ({
  items: [],
  launchedAt: new Date().toISOString(),
  loaded: false,
  setItems: (items) => set({ items, loaded: true }),
  appendItem: (item) =>
    set((state) => {
      scheduleSave();
      return { items: [...state.items, item] };
    }),
  updateItem: (item) =>
    set((state) => {
      scheduleSave();
      return { items: state.items.map((i) => (i.id === item.id ? item : i)) };
    }),
  removeItem: (id) =>
    set((state) => {
      scheduleSave();
      return { items: state.items.filter((i) => i.id !== id) };
    }),
}));

export function libraryItem(id: string): GalleryItem | undefined {
  return useLibrary.getState().items.find((i) => i.id === id);
}

/** Gallery order: oldest first (generation order). */
export function sortedItems(items: GalleryItem[]): GalleryItem[] {
  return [...items].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

// MARK: Loading / persistence

export async function initLibrary(): Promise<void> {
  await ensureDir("media");
  await ensureDir("thumbnails");
  await ensureDir("refs");
  const text = await readTextIfExists(INDEX_FILE);
  let items: GalleryItem[] = [];
  if (text) {
    try {
      items = JSON.parse(text) as GalleryItem[];
    } catch {
      items = [];
    }
  }
  // Jobs interrupted by quitting the app can't be resumed; mark them failed.
  for (const item of items) {
    if (item.status.state === "generating") {
      item.status = {
        state: "failed",
        message: "Interrupted — the app quit while this was generating.",
      };
    }
  }
  useLibrary.getState().setItems(items);
}

let saveTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleSave(): void {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    saveTimer = null;
    const items = useLibrary.getState().items;
    void writeText(INDEX_FILE, JSON.stringify(items, null, 2));
  }, 500);
}

// MARK: File paths

export function mediaPath(item: GalleryItem): string | null {
  return item.fileName ? `media/${item.fileName}` : null;
}

export function thumbnailPath(item: GalleryItem): string | null {
  return item.thumbnailFileName ? `thumbnails/${item.thumbnailFileName}` : null;
}

export function mediaURL(item: GalleryItem): Promise<string | null> {
  const path = mediaPath(item);
  return path ? fileDisplayURL(path) : Promise.resolve(null);
}

export function thumbnailURL(item: GalleryItem): Promise<string | null> {
  const path = thumbnailPath(item);
  return path ? fileDisplayURL(path) : Promise.resolve(null);
}

// MARK: Media/ref writing

export async function writeMedia(
  bytes: Uint8Array,
  id: string,
  fileExtension: string
): Promise<string> {
  const name = `${id}.${fileExtension}`;
  await writeBytes(`media/${name}`, bytes);
  return name;
}

export async function writeThumbnail(bytes: Uint8Array, id: string): Promise<string> {
  const name = `${id}.jpg`;
  await writeBytes(`thumbnails/${name}`, bytes);
  return name;
}

export async function writeRef(bytes: Uint8Array, id: string, index: number): Promise<string> {
  const ext = mimeForBytes(bytes) === "image/png" ? "png" : "jpg";
  const name = `${id}-ref${index}.${ext}`;
  await writeBytes(`refs/${name}`, bytes);
  return name;
}

export function readRefBytes(item: GalleryItem): Promise<(Uint8Array | null)[]> {
  return Promise.all(item.refFileNames.map((name) => readBytes(`refs/${name}`)));
}

export function readEndRefBytes(item: GalleryItem): Promise<Uint8Array | null> {
  return item.endRefFileName
    ? readBytes(`refs/${item.endRefFileName}`)
    : Promise.resolve(null);
}

export function readMediaBytes(item: GalleryItem): Promise<Uint8Array | null> {
  const path = mediaPath(item);
  return path ? readBytes(path) : Promise.resolve(null);
}

// MARK: Delete

export async function deleteItem(item: GalleryItem): Promise<void> {
  useLibrary.getState().removeItem(item.id);
  const files: string[] = [];
  if (item.fileName) files.push(`media/${item.fileName}`);
  if (item.thumbnailFileName) files.push(`thumbnails/${item.thumbnailFileName}`);
  files.push(...item.refFileNames.map((n) => `refs/${n}`));
  if (item.endRefFileName) files.push(`refs/${item.endRefFileName}`);
  for (const file of files) {
    await removeFile(file);
  }
}

// MARK: Download to Downloads

/** Copy an item's media file to Downloads with a readable, unique name. */
export async function downloadToDownloads(item: GalleryItem): Promise<void> {
  const path = mediaPath(item);
  if (!path) throw new Error("media file missing");
  const date = new Date(item.createdAt);
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}`;
  const base = `${item.modelID}-${stamp}`;
  const ext = item.fileName!.split(".").pop()!;
  if (await copyToDownloads(path, `${base}.${ext}`)) return;
  for (let counter = 2; counter < 100; counter++) {
    if (await copyToDownloads(path, `${base}-${counter}.${ext}`)) return;
  }
  throw new Error("could not find a free file name");
}
