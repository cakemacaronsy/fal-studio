// Port of Sources/Services/FALClient.swift — sync https://fal.run for images,
// https://queue.fal.run + status polling for video.

import { JSONValue, MediaFile } from "./types";
import { httpFetch } from "./platform";
import { base64Decode } from "./imageEncoding";

export class FALError extends Error {
  readonly kind: "noAPIKey" | "http" | "badResponse" | "timeout" | "cancelled";
  readonly httpCode?: number;
  readonly body?: string;

  constructor(
    kind: FALError["kind"],
    message: string,
    httpCode?: number,
    body?: string
  ) {
    super(message);
    this.kind = kind;
    this.httpCode = httpCode;
    this.body = body;
  }

  static noAPIKey(): FALError {
    return new FALError("noAPIKey", "No FAL API key. Add one in Settings.");
  }

  static http(code: number, body: string): FALError {
    const detail = body.slice(0, 300);
    return new FALError(
      "http",
      `FAL returned HTTP ${code}${detail ? `: ${detail}` : ""}`,
      code,
      body
    );
  }

  static badResponse(message: string): FALError {
    return new FALError("badResponse", `Unexpected FAL response: ${message}`);
  }

  static timeout(): FALError {
    return new FALError("timeout", "Timed out waiting for the generation to finish.");
  }

  /** True when the failure looks like Seedance's input content filter
   *  (photorealistic-face / IP moderation) rather than a technical error. */
  get isModerationBlock(): boolean {
    if (this.kind !== "http" || !this.body) return false;
    const text = this.body.toLowerCase();
    const markers = [
      "moderation", "content policy", "content_policy", "not eligible",
      "flagged", "sensitive", "risk control", "face", "portrait",
      "violat", "prohibited", "rejected by", "safety",
    ];
    return markers.some((m) => text.includes(m));
  }
}

export type StatusUpdate = (status: string | null, requestID: string | null) => void;

export interface FALClientLike {
  generate(
    endpoint: string,
    queued: boolean,
    payload: Record<string, JSONValue>,
    onUpdate: StatusUpdate,
    signal: AbortSignal
  ): Promise<MediaFile[]>;

  /** One-shot text generation (Improve Prompt) via fal's openrouter/router. */
  generateText(model: string, systemPrompt: string, prompt: string): Promise<string>;
}

const QUEUE_TIMEOUT_MS = 1800_000;
const POLL_INTERVAL_MS = 5_000;

export class FALClient implements FALClientLike {
  constructor(private apiKey: string) {}

  async generate(
    endpoint: string,
    queued: boolean,
    payload: Record<string, JSONValue>,
    onUpdate: StatusUpdate,
    signal: AbortSignal
  ): Promise<MediaFile[]> {
    let result: Record<string, JSONValue>;
    if (queued) {
      result = await this.runQueued(endpoint, payload, onUpdate, signal);
    } else {
      onUpdate("GENERATING", null);
      result = await this.postJSON(`https://fal.run/${endpoint}`, payload, signal);
    }
    onUpdate("DOWNLOADING", null);
    return this.collectMedia(result, signal);
  }

  async generateText(model: string, systemPrompt: string, prompt: string): Promise<string> {
    const payload: Record<string, JSONValue> = {
      model,
      system_prompt: systemPrompt,
      prompt,
      temperature: 0.7,
      max_tokens: 1200,
    };
    const result = await this.postJSON(
      "https://fal.run/openrouter/router",
      payload,
      new AbortController().signal
    );
    const output = result.output;
    if (typeof output !== "string" || output.length === 0) {
      throw FALError.badResponse("LLM returned no output");
    }
    return output;
  }

  // MARK: Queue flow (video)

  private async runQueued(
    endpoint: string,
    payload: Record<string, JSONValue>,
    onUpdate: StatusUpdate,
    signal: AbortSignal
  ): Promise<Record<string, JSONValue>> {
    const job = await this.postJSON(`https://queue.fal.run/${endpoint}`, payload, signal);
    const statusURL = typeof job.status_url === "string" ? job.status_url : null;
    const responseURL = typeof job.response_url === "string" ? job.response_url : null;
    if (!statusURL || !responseURL) {
      throw FALError.badResponse("queue submission had no status_url/response_url");
    }
    onUpdate("IN_QUEUE", typeof job.request_id === "string" ? job.request_id : null);

    const deadline = Date.now() + QUEUE_TIMEOUT_MS;
    for (;;) {
      if (Date.now() > deadline) throw FALError.timeout();
      const status = await this.getJSON(statusURL, signal);
      const state = typeof status.status === "string" ? status.status : "UNKNOWN";
      onUpdate(state, null);
      if (state === "COMPLETED") break;
      await sleep(POLL_INTERVAL_MS, signal);
    }
    return this.getJSON(responseURL, signal);
  }

  // MARK: Result parsing

  private async collectMedia(
    result: Record<string, JSONValue>,
    signal: AbortSignal
  ): Promise<MediaFile[]> {
    let entries: Record<string, JSONValue>[] = [];
    const images = result.images;
    const video = result.video;
    const videos = result.videos;
    if (Array.isArray(images)) {
      entries = images.filter(isObject);
    } else if (isObject(video)) {
      entries = [video];
    } else if (Array.isArray(videos)) {
      entries = videos.filter(isObject);
    }
    if (entries.length === 0) {
      const raw = JSON.stringify(result).slice(0, 500);
      throw FALError.badResponse(`no media in response: ${raw}`);
    }
    const files: MediaFile[] = [];
    for (const entry of entries) {
      const url = typeof entry.url === "string" ? entry.url : null;
      if (!url) continue;
      const ext = fileExtensionFor(entry, url);
      if (url.startsWith("data:")) {
        const comma = url.indexOf(",");
        if (comma < 0) throw FALError.badResponse("undecodable data URI in result");
        try {
          files.push({ bytes: base64Decode(url.slice(comma + 1)), fileExtension: ext });
        } catch {
          throw FALError.badResponse("undecodable data URI in result");
        }
      } else {
        files.push({ bytes: await this.download(url, signal), fileExtension: ext });
      }
    }
    if (files.length === 0) throw FALError.badResponse("media entries had no URLs");
    return files;
  }

  // MARK: HTTP helpers

  private async postJSON(
    url: string,
    payload: Record<string, JSONValue>,
    signal: AbortSignal
  ): Promise<Record<string, JSONValue>> {
    return this.perform(url, {
      method: "POST",
      headers: {
        Authorization: `Key ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
      signal,
    });
  }

  private async getJSON(url: string, signal: AbortSignal): Promise<Record<string, JSONValue>> {
    return this.perform(url, {
      headers: { Authorization: `Key ${this.apiKey}` },
      signal,
    });
  }

  private async perform(url: string, init: RequestInit): Promise<Record<string, JSONValue>> {
    const response = await httpFetch(url, init);
    const text = await response.text();
    if (!response.ok) {
      throw FALError.http(response.status, text);
    }
    try {
      const parsed = JSON.parse(text);
      if (!isObject(parsed)) throw new Error("not an object");
      return parsed;
    } catch {
      throw FALError.badResponse(text.slice(0, 300) || "undecodable body");
    }
  }

  private async download(url: string, signal: AbortSignal): Promise<Uint8Array> {
    const response = await httpFetch(url, { signal });
    if (!response.ok) {
      throw FALError.http(response.status, "downloading result media");
    }
    return new Uint8Array(await response.arrayBuffer());
  }
}

function isObject(value: JSONValue | undefined): value is Record<string, JSONValue> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fileExtensionFor(entry: Record<string, JSONValue>, url: string): string {
  const contentType = typeof entry.content_type === "string" ? entry.content_type : null;
  if (contentType) {
    if (contentType.includes("mp4") || contentType.includes("video")) return "mp4";
    if (contentType.includes("jpeg") || contentType.includes("jpg")) return "jpeg";
    if (contentType.includes("png")) return "png";
  }
  if (url.startsWith("data:image/jpeg")) return "jpeg";
  let path = "";
  try {
    path = new URL(url).pathname.split(".").pop()?.toLowerCase() ?? "";
  } catch {
    path = "";
  }
  if (["png", "jpeg", "jpg", "mp4", "webm", "mov"].includes(path)) {
    return path === "jpg" ? "jpeg" : path;
  }
  return "png";
}

export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(new DOMException("Aborted", "AbortError"));
    };
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}
