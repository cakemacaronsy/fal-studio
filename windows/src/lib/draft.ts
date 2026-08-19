// Port of Sources/Views/ControlPanel/GenerationDraft.swift — the in-progress
// state of the control panel, including the family → endpoint-variant
// resolution driven by the provided reference images.

import { create } from "zustand";
import {
  GalleryItem,
  JSONValue,
  MediaKind,
  ModelSpec,
  ParameterSpec,
  paramDefaultValue,
} from "./types";
import {
  allSpecs,
  defaultFamilyID,
  familyFor,
  familyIDForSpecID,
  specFor,
} from "./catalog";
import { estimateCost } from "./pricing";
import { EncodedImage, encodeForUpload, bytesToBlob } from "./imageEncoding";
import { readEndRefBytes, readMediaBytes, readRefBytes } from "./library";
import { tr } from "./lang";

/** A reference image the user dropped in, already encoded for upload. */
export interface RefImage {
  id: string;
  encoded: EncodedImage;
  previewURL: string; // object URL for display
  annotated: boolean; // true after Mark up (red edit markings baked in)
}

export function makeRefImage(encoded: EncodedImage, annotated = false): RefImage {
  return {
    id: crypto.randomUUID(),
    encoded,
    previewURL: URL.createObjectURL(bytesToBlob(encoded.bytes, encoded.mime)),
    annotated,
  };
}

interface DraftState {
  mode: MediaKind;
  /** A family id ("fam-seedance"). */
  modelID: string;
  prompt: string;
  paramValues: Record<string, JSONValue>;
  refImages: RefImage[];
  endImage: RefImage | null;

  // Improve Prompt state
  jsonMode: boolean;
  isImproving: boolean;
  promptBackup: string | null; // enables revert after Improve
  improveError: string | null;

  setPrompt: (prompt: string) => void;
  setJsonMode: (on: boolean) => void;
  setValue: (key: string, value: JSONValue) => void;
  selectMode: (mode: MediaKind) => void;
  selectModel: (id: string) => void;
  addRefImages: (files: Blob[]) => Promise<void>;
  removeRefImage: (id: string) => void;
  setEndImage: (file: Blob | null) => Promise<void>;
  applyAnnotation: (encoded: EncodedImage, refID: string) => void;
  applyImproved: (improved: string) => void;
  revertImproved: () => void;
  setImproving: (on: boolean, error?: string | null) => void;
  makeVideoFrom: (item: GalleryItem) => Promise<void>;
  useAsReference: (item: GalleryItem) => Promise<void>;
  loadItem: (item: GalleryItem) => Promise<void>;
}

function releaseRef(ref: RefImage | null): void {
  if (ref) URL.revokeObjectURL(ref.previewURL);
}

export const useDraft = create<DraftState>((set, get) => ({
  mode: "image",
  modelID: defaultFamilyID("image"),
  prompt: "",
  paramValues: {},
  refImages: [],
  endImage: null,
  jsonMode: false,
  isImproving: false,
  promptBackup: null,
  improveError: null,

  setPrompt: (prompt) => set({ prompt }),
  setJsonMode: (jsonMode) => set({ jsonMode }),
  setValue: (key, value) =>
    set((state) => ({ paramValues: { ...state.paramValues, [key]: value } })),

  selectMode: (mode) => {
    if (mode === get().mode) return;
    set({ mode });
    get().selectModel(defaultFamilyID(mode));
  },

  selectModel: (id) => {
    // Normalize: family id stays; a concrete spec id (old gallery items)
    // maps back to its family.
    let modelID: string;
    if (familyFor(id)) {
      modelID = id;
    } else {
      const familyID = familyIDForSpecID(id);
      if (!familyID) return;
      modelID = familyID;
    }
    set({ modelID });

    // Trim reference images to the new model's capability.
    const state = get();
    const max = maxRefImages(state);
    const trimmed = state.refImages.slice(0, Math.max(max, 0));
    state.refImages.slice(Math.max(max, 0)).forEach(releaseRef);
    let endImage = state.endImage;
    if (!supportsEndFrame({ ...state, refImages: trimmed, endImage })) {
      releaseRef(endImage);
      endImage = null;
    }
    set({ refImages: trimmed, endImage });

    // Keep values whose parameter still exists with the same kind of options;
    // reset the rest to the new model's defaults.
    const newSpec = draftSpec(get());
    const migrated: Record<string, JSONValue> = {};
    for (const param of newSpec.parameters) {
      const old = get().paramValues[param.key];
      migrated[param.key] =
        old !== undefined && isValidValue(old, param) ? old : paramDefaultValue(param);
    }
    set({ paramValues: migrated });
  },

  addRefImages: async (files) => {
    for (const file of files) {
      const state = get();
      if (state.refImages.length >= maxRefImages(state)) break;
      try {
        const encoded = await encodeForUpload(file);
        set((s) => ({ refImages: [...s.refImages, makeRefImage(encoded)] }));
      } catch {
        // unreadable file — skip, matching the macOS behavior
      }
    }
  },

  removeRefImage: (id) =>
    set((state) => {
      const removed = state.refImages.find((r) => r.id === id);
      releaseRef(removed ?? null);
      return { refImages: state.refImages.filter((r) => r.id !== id) };
    }),

  setEndImage: async (file) => {
    releaseRef(get().endImage);
    if (!file) {
      set({ endImage: null });
      return;
    }
    try {
      const encoded = await encodeForUpload(file);
      set({ endImage: makeRefImage(encoded) });
    } catch {
      // unreadable file — leave unchanged
    }
  },

  applyAnnotation: (encoded, refID) => {
    const state = get();
    const index = state.refImages.findIndex((r) => r.id === refID);
    if (index >= 0) {
      releaseRef(state.refImages[index]);
      const refImages = [...state.refImages];
      refImages[index] = makeRefImage(encoded, true);
      set({ refImages });
    } else if (state.endImage?.id === refID) {
      releaseRef(state.endImage);
      set({ endImage: makeRefImage(encoded, true) });
    }
  },

  applyImproved: (improved) =>
    set((state) => ({ promptBackup: state.prompt, prompt: improved })),

  revertImproved: () =>
    set((state) =>
      state.promptBackup !== null
        ? { prompt: state.promptBackup, promptBackup: null }
        : {}
    ),

  setImproving: (isImproving, improveError = null) =>
    set({ isImproving, improveError }),

  /** One-click image→video (OpenArt-style): jump to the default video family
   *  with this image as the start frame. */
  makeVideoFrom: async (item) => {
    const bytes = await readMediaBytes(item);
    if (!bytes) return;
    get().refImages.forEach(releaseRef);
    releaseRef(get().endImage);
    set({ mode: "video", refImages: [], endImage: null });
    get().selectModel(defaultFamilyID("video"));
    await get().addRefImages([bytesToBlob(bytes)]);
  },

  /** Load a finished work's image as a reference. If the current model takes
   *  no images at all, switch to the default video family (i2v). */
  useAsReference: async (item) => {
    const bytes = await readMediaBytes(item);
    if (!bytes) return;
    let state = get();
    if (maxRefImages(state) === 0) {
      set({ mode: "video" });
      state.selectModel(defaultFamilyID("video"));
    }
    state = get();
    if (maxRefImages(state) === 1) {
      state.refImages.forEach(releaseRef);
      set({ refImages: [] });
    }
    await get().addRefImages([bytesToBlob(bytes)]);
  },

  /** Restore a gallery item's prompt, model, and settings into the panel. */
  loadItem: async (item) => {
    const state = get();
    state.refImages.forEach(releaseRef);
    releaseRef(state.endImage);
    set({ mode: item.kind, refImages: [], endImage: null });
    if (familyIDForSpecID(item.modelID)) {
      get().selectModel(item.modelID);
    } else {
      get().selectModel(defaultFamilyID(item.kind));
    }
    set({ prompt: item.prompt, promptBackup: null });
    const spec = draftSpec(get());
    const paramValues = { ...get().paramValues };
    for (const param of spec.parameters) {
      const value = item.parameters[param.key];
      if (value !== undefined && isValidValue(value, param)) {
        paramValues[param.key] = value;
      }
    }
    set({ paramValues });
    const refs = (await readRefBytes(item)).filter((b): b is Uint8Array => b !== null);
    await get().addRefImages(refs.map((b) => bytesToBlob(b)));
    const endBytes = await readEndRefBytes(item);
    if (endBytes) await get().setEndImage(bytesToBlob(endBytes));
  },
}));

function isValidValue(value: JSONValue, param: ParameterSpec): boolean {
  switch (param.kind.type) {
    case "choice":
      return typeof value === "string" && param.kind.options.includes(value);
    case "toggle":
      return typeof value === "boolean";
    case "stepper":
      return (
        typeof value === "number" &&
        value >= param.kind.min &&
        value <= param.kind.max
      );
  }
}

// MARK: Derived state (used by components via useDraft selectors)

type DraftLike = Pick<DraftState, "mode" | "modelID" | "refImages" | "endImage">;

function resolvedVariantID(state: DraftLike): string {
  const family = familyFor(state.modelID);
  if (!family) return state.modelID;
  if (state.refImages.length === 0 && state.endImage === null) {
    return family.baseSpecID;
  }
  if (state.refImages.length >= 2 && family.multipleSpecID) {
    return family.multipleSpecID;
  }
  if (family.startEndSpecID) {
    return family.startEndSpecID;
  }
  return family.multipleSpecID ?? family.baseSpecID;
}

/** The concrete endpoint spec, resolved from the family + the reference
 *  images currently provided: none → text-to-x, one (or an end frame) →
 *  image-to-video, several → edit/reference variant. */
export function draftSpec(state: DraftLike): ModelSpec {
  return specFor(resolvedVariantID(state)) ?? allSpecs[0];
}

/** Short label showing which endpoint the current inputs resolve to. */
export function variantCaption(state: DraftLike): string | null {
  const family = familyFor(state.modelID);
  if (!family) return null;
  const variant = resolvedVariantID(state);
  if (variant === family.baseSpecID) {
    return state.mode === "video"
      ? tr("Mode: text → video", "模式:文生影片")
      : tr("Mode: text → image", "模式:文生圖");
  }
  if (variant === family.startEndSpecID) {
    return tr("Mode: image → video (start frame)", "模式:圖生影片(起始畫格)");
  }
  return state.mode === "video"
    ? tr("Mode: references → video", "模式:參考圖生影片")
    : tr("Mode: image edit", "模式:圖片編輯");
}

/** Capacity across the family's variants (so the drop zone can offer every
 *  possibility and the variant resolves from what's provided). */
export function maxRefImages(state: DraftLike): number {
  const family = familyFor(state.modelID);
  if (family) {
    let capacity = family.startEndSpecID ? 1 : 0;
    if (family.multipleSpecID) {
      const multipleSpec = specFor(family.multipleSpecID);
      if (multipleSpec && multipleSpec.refImages.type === "multiple") {
        capacity = Math.max(capacity, multipleSpec.refImages.max);
      }
    }
    return capacity;
  }
  const spec = draftSpec(state);
  switch (spec.refImages.type) {
    case "none": return 0;
    case "startEnd": return 1;
    case "multiple": return spec.refImages.max;
  }
}

/** End frame is only meaningful while the inputs resolve to the
 *  image-to-video variant (zero or one start image). */
export function supportsEndFrame(state: DraftLike): boolean {
  const family = familyFor(state.modelID);
  if (family) {
    if (!family.startEndSpecID || state.refImages.length > 1) return false;
    return specFor(family.startEndSpecID)?.endImagePayloadKey !== undefined;
  }
  const spec = draftSpec(state);
  return spec.refImages.type === "startEnd" && spec.endImagePayloadKey !== undefined;
}

export function draftEstimatedCost(
  state: DraftLike & Pick<DraftState, "paramValues">
): number {
  return estimateCost(draftSpec(state), state.paramValues);
}

export function hasAnnotatedRefs(state: DraftLike): boolean {
  return (
    state.refImages.some((r) => r.annotated) || state.endImage?.annotated === true
  );
}
