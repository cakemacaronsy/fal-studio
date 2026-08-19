// Port of Sources/Services/GenerationManager.swift — orchestrates generation
// jobs: creates the placeholder gallery item, runs the FAL call (many can run
// concurrently), and flips the item to completed/failed. Also handles Cancel,
// Retry, the Improve Prompt call, and Seedance's face-filter fallback.

import { create } from "zustand";
import {
  GalleryItem,
  JSONValue,
  MediaFile,
  ModelSpec,
  paramDefaultValue,
} from "./types";
import { buildPayload, seedreamImageSize } from "./payload";
import { estimateCost } from "./pricing";
import { FALClient, FALClientLike, FALError } from "./falClient";
import { MockFALClient } from "./mockClient";
import { effectiveKey } from "./keyStore";
import { useSettings } from "./settings";
import { improverSystemPrompt } from "./improver";
import {
  libraryItem,
  readEndRefBytes,
  readRefBytes,
  useLibrary,
  writeMedia,
  writeRef,
  writeThumbnail,
  mediaURL,
} from "./library";
import { dataURI, imageThumbnail, pixelSize, videoThumbnail } from "./imageEncoding";
import { notify } from "./platform";
import { specFor } from "./catalog";
import { tr } from "./lang";

interface GenerationState {
  /** Live queue status per generating item ("IN_QUEUE", "IN_PROGRESS", ...). */
  liveStatus: Record<string, string>;
  running: Record<string, boolean>;
  setStatus: (id: string, status: string | null) => void;
  setRunning: (id: string, running: boolean) => void;
}

export const useGeneration = create<GenerationState>((set) => ({
  liveStatus: {},
  running: {},
  setStatus: (id, status) =>
    set((state) => {
      const liveStatus = { ...state.liveStatus };
      if (status === null) delete liveStatus[id];
      else liveStatus[id] = status;
      return { liveStatus };
    }),
  setRunning: (id, running) =>
    set((state) => {
      const map = { ...state.running };
      if (running) map[id] = true;
      else delete map[id];
      return { running: map };
    }),
}));

const controllers = new Map<string, AbortController>();

async function makeClient(): Promise<FALClientLike> {
  if (useSettings.getState().mockMode) return new MockFALClient();
  const key = await effectiveKey();
  if (!key) throw FALError.noAPIKey();
  return new FALClient(key);
}

// MARK: Improve Prompt

/** Rewrite the prompt per the selected model's official prompting guide, via
 *  fal's openrouter/router (cheap LLM, same FAL key). */
export async function improvePrompt(
  prompt: string,
  spec: ModelSpec,
  jsonMode: boolean
): Promise<string> {
  const client = await makeClient();
  const llm = useSettings.getState().improveModel.trim() || "deepseek/deepseek-chat";
  const system = improverSystemPrompt(spec, jsonMode, prompt);
  let improved = (await client.generateText(llm, system, prompt)).trim();
  // Strip markdown fences some models add despite instructions.
  if (improved.startsWith("```")) {
    improved = improved.replaceAll("```json", "").replaceAll("```", "").trim();
  }
  return improved;
}

// MARK: Orientation hint

/** Quietly append a composition hint matching the chosen aspect ratio, so
 *  results fill the frame's orientation. Skipped when the prompt already talks
 *  about orientation, or the ratio is auto/adaptive/missing. */
export function applyOrientationHint(
  prompt: string,
  spec: ModelSpec,
  values: Record<string, JSONValue>
): string {
  const aspectParam = spec.parameters.find((p) => p.key === "aspect_ratio");
  if (!aspectParam) return prompt;
  const raw =
    values.aspect_ratio ?? paramDefaultValue(aspectParam);
  const ratio = typeof raw === "string" ? raw : "auto";
  const parts = ratio.split(":").map(Number).filter((n) => Number.isFinite(n));
  if (parts.length !== 2 || parts[0] <= 0 || parts[1] <= 0) return prompt;

  const lowered = prompt.toLowerCase();
  const orientationWords = [
    "landscape", "portrait", "vertical", "horizontal", "square", "composition", "framing",
  ];
  if (orientationWords.some((w) => lowered.includes(w))) return prompt;

  let hint: string;
  if (parts[0] > parts[1]) {
    hint = "Wide landscape composition.";
  } else if (parts[0] < parts[1]) {
    hint = "Vertical portrait composition, full-height framing.";
  } else {
    hint = "Square composition.";
  }
  return `${prompt}\n\n${hint}`;
}

// MARK: Start

export async function startGeneration(
  spec: ModelSpec,
  rawPrompt: string,
  values: Record<string, JSONValue>,
  refDatas: Uint8Array[],
  endRefData: Uint8Array | null
): Promise<void> {
  const prompt = applyOrientationHint(rawPrompt, spec, values);
  const id = crypto.randomUUID();
  const refNames: string[] = [];
  for (let index = 0; index < refDatas.length; index++) {
    try {
      refNames.push(await writeRef(refDatas[index], id, index + 1));
    } catch {
      // ref copy is best-effort, like the macOS app
    }
  }
  let endName: string | null = null;
  if (endRefData) {
    try {
      endName = await writeRef(endRefData, id, 0);
    } catch {
      endName = null;
    }
  }

  const item: GalleryItem = {
    id,
    kind: spec.kind,
    fileName: null,
    thumbnailFileName: null,
    prompt,
    modelID: spec.id,
    endpoint: spec.endpoint,
    parameters: values,
    refFileNames: refNames,
    endRefFileName: endName,
    costEstimate: estimateCost(spec, values),
    createdAt: new Date().toISOString(),
    status: { state: "generating" },
    requestID: null,
  };
  useLibrary.getState().appendItem(item);
  launch(id, spec, prompt, values, refDatas, endRefData);
}

// MARK: Cancel / Retry

export function cancelGeneration(id: string): void {
  controllers.get(id)?.abort();
  controllers.delete(id);
  useGeneration.getState().setRunning(id, false);
  useGeneration.getState().setStatus(id, null);
  const item = libraryItem(id);
  if (item && item.status.state === "generating") {
    useLibrary.getState().updateItem({
      ...item,
      status: { state: "failed", message: "Cancelled" },
    });
  }
}

export async function retryGeneration(item: GalleryItem): Promise<void> {
  const spec = specFor(item.modelID);
  if (!spec) return;
  const refDatas = (await readRefBytes(item)).filter(
    (b): b is Uint8Array => b !== null
  );
  const endData = await readEndRefBytes(item);
  await startGeneration(spec, item.prompt, item.parameters, refDatas, endData);
}

// MARK: Job body

function launch(
  itemID: string,
  spec: ModelSpec,
  prompt: string,
  values: Record<string, JSONValue>,
  refDatas: Uint8Array[],
  endRefData: Uint8Array | null
): void {
  const controller = new AbortController();
  controllers.set(itemID, controller);
  useGeneration.getState().setRunning(itemID, true);

  void (async () => {
    try {
      const client = await makeClient();
      const payload = buildPayload(
        spec,
        prompt,
        values,
        refDatas.map((b) => dataURI(b)),
        endRefData ? dataURI(endRefData) : null
      );

      const onUpdate = (status: string | null, requestID: string | null) => {
        if (status) useGeneration.getState().setStatus(itemID, status);
        if (requestID) {
          const item = libraryItem(itemID);
          if (item) useLibrary.getState().updateItem({ ...item, requestID });
        }
      };

      let files: MediaFile[];
      try {
        files = await client.generate(
          spec.endpoint, spec.queued, payload, onUpdate, controller.signal
        );
      } catch (error) {
        if (
          error instanceof FALError &&
          error.isModerationBlock &&
          isSeedanceImageToVideo(spec) &&
          refDatas.length > 0
        ) {
          // Seedance's input filter flags photorealistic faces by pixel
          // statistics — even AI-generated ones. ByteDance's documented fix
          // for original characters: use a Seedream-rendered frame instead.
          // Re-render the frame(s) faithfully with Seedream, then retry.
          useGeneration.getState().setStatus(itemID, "RE-RENDERING FRAME (SEEDREAM)");
          const newRefs = [...refDatas];
          newRefs[0] = await rerenderFrame(refDatas[0], client, controller.signal);
          let newEnd = endRefData;
          if (endRefData) {
            newEnd = await rerenderFrame(endRefData, client, controller.signal);
          }
          useGeneration.getState().setStatus(itemID, "RETRYING");
          const retryPayload = buildPayload(
            spec,
            prompt,
            values,
            newRefs.map((b) => dataURI(b)),
            newEnd ? dataURI(newEnd) : null
          );
          files = await client.generate(
            spec.endpoint, spec.queued, retryPayload, onUpdate, controller.signal
          );
          noteFrameFallback(itemID, 1 + (endRefData ? 1 : 0));
        } else {
          throw error;
        }
      }

      if (controller.signal.aborted) return;
      await finish(itemID, files);
      await makeVideoThumbnailIfNeeded(itemID);
      notifyIfBackgrounded(prompt, true);
    } catch (error) {
      if (isAbort(error)) {
        // cancelGeneration() already marked the item.
      } else {
        fail(itemID, error instanceof Error ? error.message : String(error));
        notifyIfBackgrounded(prompt, false);
      }
    } finally {
      controllers.delete(itemID);
      useGeneration.getState().setRunning(itemID, false);
      useGeneration.getState().setStatus(itemID, null);
    }
  })();
}

function isAbort(error: unknown): boolean {
  return (
    (error instanceof DOMException && error.name === "AbortError") ||
    (error instanceof Error && error.name === "AbortError")
  );
}

// MARK: Seedance moderation fallback

function isSeedanceImageToVideo(spec: ModelSpec): boolean {
  // Covers Seedance 2.0 and 2.5 — both run the photorealistic-face input filter.
  return spec.endpoint.includes("seedance-2") && spec.endpoint.endsWith("image-to-video");
}

const SEEDREAM_EDIT_COST = 0.135;

/** Faithfully re-render a frame with Seedream so its pixel statistics read as
 *  AI-generated, which passes Seedance's input filter. */
async function rerenderFrame(
  frame: Uint8Array,
  client: FALClientLike,
  signal: AbortSignal
): Promise<Uint8Array> {
  const payload: Record<string, JSONValue> = {
    prompt:
      "Recreate this exact image with complete fidelity: identical person, face, " +
      "expression, pose, clothing, lighting, colors, background and composition. " +
      "Do not add, remove or change anything.",
    image_urls: [dataURI(frame)],
    num_images: 1,
    output_format: "png",
  };
  const size = await pixelSize(frame);
  if (size) {
    payload.image_size = seedreamImageSize(`${size.width}:${size.height}`);
  }
  const files = await client.generate(
    "bytedance/seedream/v5/pro/edit", false, payload, () => {}, signal
  );
  if (files.length === 0) {
    throw FALError.badResponse("Seedream frame re-render returned no image");
  }
  return files[0].bytes;
}

/** Record on the item that the fallback ran (visible in the detail sheet)
 *  and add the Seedream re-render cost to the estimate. */
function noteFrameFallback(itemID: string, frames: number): void {
  const old = libraryItem(itemID);
  if (!old) return;
  useLibrary.getState().updateItem({
    ...old,
    parameters: {
      ...old.parameters,
      frame_fallback: "frame re-rendered with Seedream (Seedance face filter)",
    },
    costEstimate: old.costEstimate + SEEDREAM_EDIT_COST * frames,
  });
}

// MARK: Finish / fail

/** Write media files; the first fills the original item, extras
 *  (num_images > 1) become sibling items appended right after it. */
async function finish(itemID: string, files: MediaFile[]): Promise<void> {
  const item = libraryItem(itemID);
  if (!item) return;
  const first = files[0];
  if (!first) throw FALError.badResponse("no media returned");

  const updated: GalleryItem = { ...item };
  updated.fileName = await writeMedia(first.bytes, item.id, first.fileExtension);
  if (item.kind === "image") {
    const thumb = await imageThumbnail(first.bytes);
    if (thumb) {
      try {
        updated.thumbnailFileName = await writeThumbnail(thumb, item.id);
      } catch {
        updated.thumbnailFileName = null;
      }
    }
  }
  updated.status = { state: "completed" };
  useLibrary.getState().updateItem(updated);

  const createdAt = new Date(item.createdAt);
  for (let index = 1; index < files.length; index++) {
    const extra = files[index];
    const siblingID = crypto.randomUUID();
    const sibling: GalleryItem = {
      id: siblingID,
      kind: item.kind,
      fileName: await writeMedia(extra.bytes, siblingID, extra.fileExtension),
      thumbnailFileName: null,
      prompt: item.prompt,
      modelID: item.modelID,
      endpoint: item.endpoint,
      parameters: item.parameters,
      refFileNames: [],
      endRefFileName: null,
      costEstimate: 0, // cost is attributed to the first item
      createdAt: new Date(createdAt.getTime() + index).toISOString(),
      status: { state: "completed" },
      requestID: item.requestID,
    };
    if (sibling.kind === "image") {
      const thumb = await imageThumbnail(extra.bytes);
      if (thumb) {
        try {
          sibling.thumbnailFileName = await writeThumbnail(thumb, siblingID);
        } catch {
          sibling.thumbnailFileName = null;
        }
      }
    }
    useLibrary.getState().appendItem(sibling);
  }
}

async function makeVideoThumbnailIfNeeded(itemID: string): Promise<void> {
  const item = libraryItem(itemID);
  if (!item || item.kind !== "video" || item.thumbnailFileName) return;
  const url = await mediaURL(item);
  if (!url) return;
  const thumb = await videoThumbnail(url);
  if (!thumb) return;
  try {
    const name = await writeThumbnail(thumb, item.id);
    const current = libraryItem(itemID);
    if (current) {
      useLibrary.getState().updateItem({ ...current, thumbnailFileName: name });
    }
  } catch {
    // thumbnail is cosmetic
  }
}

function fail(itemID: string, message: string): void {
  const item = libraryItem(itemID);
  if (!item || item.status.state !== "generating") return;
  useLibrary.getState().updateItem({
    ...item,
    status: { state: "failed", message },
  });
}

// MARK: Done notifications

/** Notification when a job ends while the app is in the background. */
function notifyIfBackgrounded(prompt: string, success: boolean): void {
  if (document.hasFocus()) return;
  void notify(
    success ? tr("Generation finished", "生成完成") : tr("Generation failed", "生成失敗"),
    prompt.slice(0, 80)
  );
}
