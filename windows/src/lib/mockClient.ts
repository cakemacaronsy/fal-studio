// Port of Sources/Services/MockFALClient.swift — zero-credit stand-in that
// renders a gradient placeholder image, or records a short gradient WebM for
// video models. Enabled via the Settings "Mock mode" toggle.

import { JSONValue, MediaFile } from "./types";
import { FALClientLike, StatusUpdate, sleep } from "./falClient";

export class MockFALClient implements FALClientLike {
  async generate(
    endpoint: string,
    queued: boolean,
    payload: Record<string, JSONValue>,
    onUpdate: StatusUpdate,
    signal: AbortSignal
  ): Promise<MediaFile[]> {
    const prompt = typeof payload.prompt === "string" ? payload.prompt : "";
    onUpdate(
      queued ? "IN_QUEUE" : "GENERATING",
      queued ? `mock-${crypto.randomUUID().slice(0, 8)}` : null
    );
    await sleep(1000, signal);
    if (queued) {
      onUpdate("IN_PROGRESS", null);
      await sleep(2000, signal);
    } else {
      await sleep(1000, signal);
    }
    const isVideo = endpoint.includes("video");
    if (isVideo) {
      const { bytes, ext } = await makeMockVideo(prompt);
      return [{ bytes, fileExtension: ext }];
    }
    const count = typeof payload.num_images === "number" ? payload.num_images : 1;
    const files: MediaFile[] = [];
    for (let i = 0; i < count; i++) {
      files.push({ bytes: await makeMockImage(prompt, i), fileExtension: "png" });
    }
    return files;
  }

  async generateText(model: string, _systemPrompt: string, prompt: string): Promise<string> {
    await sleep(1000);
    return `[MOCK improved via ${model}] ${prompt} — detailed subject, balanced composition, cinematic lighting, 50mm lens.`;
  }
}

// MARK: Placeholder rendering

function hueSeed(text: string): number {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) | 0;
  }
  return (Math.abs(hash) % 360) / 360;
}

function hsvColor(h: number): string {
  const hh = ((h % 1) + 1) % 1;
  const i = Math.floor(hh * 6);
  const f = hh * 6 - i;
  const v = 0.9;
  const s = 0.55;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  const rgb =
    i % 6 === 0 ? [v, t, p] :
    i % 6 === 1 ? [q, v, p] :
    i % 6 === 2 ? [p, v, t] :
    i % 6 === 3 ? [p, q, v] :
    i % 6 === 4 ? [t, p, v] : [v, p, q];
  return `rgb(${rgb.map((c) => Math.round(c * 255)).join(",")})`;
}

function drawFrame(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  prompt: string,
  variant: number,
  phase: number
): void {
  const seed = hueSeed(prompt) + variant * 0.13 + phase * 0.2;
  const gradient = ctx.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, hsvColor(seed));
  gradient.addColorStop(1, hsvColor(seed + 0.35));
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = "rgba(255,255,255,0.92)";
  ctx.font = "20px system-ui, sans-serif";
  ctx.fillText(`MOCK · ${prompt.slice(0, 48)}`, 24, height - 28);
}

export async function makeMockImage(prompt: string, variant: number): Promise<Uint8Array> {
  const canvas = document.createElement("canvas");
  canvas.width = 1024;
  canvas.height = 576;
  drawFrame(canvas.getContext("2d")!, 1024, 576, prompt, variant, 0);
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/png")
  );
  if (!blob) throw new Error("mock render failed");
  return new Uint8Array(await blob.arrayBuffer());
}

/** 2-second shifting gradient, recorded as WebM via MediaRecorder. */
export async function makeMockVideo(
  prompt: string
): Promise<{ bytes: Uint8Array; ext: string }> {
  if (typeof MediaRecorder === "undefined") {
    throw new Error("mock video needs MediaRecorder support in this webview");
  }
  const width = 640;
  const height = 360;
  const fps = 12;
  const seconds = 2;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d")!;
  const stream = canvas.captureStream(fps);
  const mimeType = ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"].find(
    (t) => MediaRecorder.isTypeSupported(t)
  );
  const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
  const chunks: BlobPart[] = [];
  recorder.ondataavailable = (e) => {
    if (e.data.size > 0) chunks.push(e.data);
  };
  const stopped = new Promise<void>((resolve) => {
    recorder.onstop = () => resolve();
  });
  recorder.start();
  const totalFrames = fps * seconds;
  for (let frame = 0; frame < totalFrames; frame++) {
    drawFrame(ctx, width, height, prompt, 0, frame / totalFrames);
    await sleep(1000 / fps);
  }
  recorder.stop();
  await stopped;
  const blob = new Blob(chunks, { type: "video/webm" });
  return { bytes: new Uint8Array(await blob.arrayBuffer()), ext: "webm" };
}
