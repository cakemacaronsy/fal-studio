// Core types — a faithful TypeScript port of the macOS app's
// Sources/Models/{ModelCatalog,GalleryItem,JSONValue}.swift.

export type MediaKind = "image" | "video";

/** A JSON-representable value, used for payloads and persisted settings. */
export type JSONValue =
  | string
  | number
  | boolean
  | null
  | JSONValue[]
  | { [key: string]: JSONValue };

/** What kind of reference-image input a model accepts. */
export type RefImageSupport =
  | { type: "none" }
  | { type: "startEnd" } // start frame plus an optional end frame
  | { type: "multiple"; max: number }; // edit / reference-to-video models

export type ParamKind =
  | { type: "choice"; options: string[]; defaultValue: string }
  | { type: "toggle"; defaultValue: boolean }
  | { type: "stepper"; min: number; max: number; defaultValue: number };

export type ParamEncoding = "raw" | "stringToInt" | "seedreamImageSize";

export interface ParameterSpec {
  key: string; // payload key ("aspect_ratio", "resolution", ...)
  label: string; // chip label
  kind: ParamKind;
  encoding?: ParamEncoding;
}

export type PricingRule =
  | { type: "perImage"; byResolution: Record<string, number>; base: number }
  | {
      type: "perSecond";
      byResolution: Record<string, number>;
      base: number;
      audioSurcharge: number | null;
      autoDurationAssumption: number;
    }
  | { type: "flat"; cost: number };

export interface ModelSpec {
  id: string;
  displayName: string;
  kind: MediaKind;
  endpoint: string; // path after fal.run / queue.fal.run
  queued: boolean; // true → queue API (video)
  refImages: RefImageSupport;
  refPayloadKey?: string; // "image_urls" / "image_url" / "start_image_url" / "reference_image_urls"
  endImagePayloadKey?: string; // "end_image_url"
  fixedPayload?: Record<string, JSONValue>;
  parameters: ParameterSpec[];
  pricing: PricingRule;
}

export interface ModelFamily {
  id: string;
  displayName: string;
  kind: MediaKind;
  baseSpecID: string; // no reference images
  startEndSpecID?: string; // start frame (+ optional end frame)
  multipleSpecID?: string; // multiple references / edit
}

export type ItemStatus =
  | { state: "generating" }
  | { state: "completed" }
  | { state: "failed"; message: string };

/** One work on the gallery wall. Persisted in library.json. */
export interface GalleryItem {
  id: string;
  kind: MediaKind;
  fileName: string | null; // media/<id>.png|.mp4, null while generating
  thumbnailFileName: string | null; // thumbnails/<id>.jpg
  prompt: string;
  modelID: string;
  endpoint: string;
  /** UI-level parameter values (pre-encoding, human-readable). */
  parameters: Record<string, JSONValue>;
  refFileNames: string[]; // refs/<id>-ref<N> copies of the inputs
  endRefFileName: string | null;
  costEstimate: number;
  createdAt: string; // ISO 8601
  status: ItemStatus;
  requestID: string | null; // FAL queue request id (videos)
}

export interface MediaFile {
  bytes: Uint8Array;
  fileExtension: string; // "png" / "jpeg" / "mp4" / "webm"
}

export function paramDefaultValue(param: ParameterSpec): JSONValue {
  switch (param.kind.type) {
    case "choice":
      return param.kind.defaultValue;
    case "toggle":
      return param.kind.defaultValue;
    case "stepper":
      return param.kind.defaultValue;
  }
}

/** Human-readable form for the settings list in the detail sheet. */
export function displayString(value: JSONValue): string {
  if (value === null) return "—";
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  if (typeof value === "boolean") return value ? "on" : "off";
  if (Array.isArray(value)) return value.map(displayString).join(", ");
  return Object.keys(value)
    .sort()
    .map((k) => `${k}: ${displayString(value[k])}`)
    .join(", ");
}

export function stringValue(value: JSONValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

export function intValue(value: JSONValue | undefined): number | null {
  return typeof value === "number" ? value : null;
}

export function boolValue(value: JSONValue | undefined): boolean | null {
  return typeof value === "boolean" ? value : null;
}
