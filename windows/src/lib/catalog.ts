// Port of Sources/Models/ModelCatalog.swift — the full model catalog with
// family → variant endpoint routing.

import { MediaKind, ModelFamily, ModelSpec, ParameterSpec } from "./types";
import { Pricing } from "./pricing";

// MARK: Shared option lists

const grokAspects = [
  "2:1", "20:9", "19.5:9", "16:9", "3:2", "4:3", "1:1",
  "3:4", "2:3", "9:16", "9:19.5", "9:20", "1:2",
];
const seedanceAspects = ["auto", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"];
const range = (from: number, to: number): string[] =>
  Array.from({ length: to - from + 1 }, (_, i) => String(from + i));
const seedanceDurations = ["auto", ...range(4, 15)];
const seedance25Durations = ["auto", ...range(4, 30)];
const minimaxAspects = ["16:9", "21:9", "4:3", "1:1", "3:4", "9:16"];
const minimaxDurations = range(5, 15);
const klingDurations = range(3, 15);

const choice = (
  key: string,
  label: string,
  options: string[],
  defaultValue: string,
  encoding?: "stringToInt" | "seedreamImageSize"
): ParameterSpec => ({
  key,
  label,
  kind: { type: "choice", options, defaultValue },
  ...(encoding ? { encoding } : {}),
});

const toggle = (key: string, label: string, defaultValue: boolean): ParameterSpec => ({
  key,
  label,
  kind: { type: "toggle", defaultValue },
});

const stepper = (
  key: string,
  label: string,
  min: number,
  max: number,
  defaultValue: number
): ParameterSpec => ({
  key,
  label,
  kind: { type: "stepper", min, max, defaultValue },
});

function seedanceParams(resolutions: string[]): ParameterSpec[] {
  return [
    choice("resolution", "Resolution", resolutions, "720p"),
    choice("duration", "Duration", seedanceDurations, "auto"),
    choice("aspect_ratio", "Aspect", seedanceAspects, "auto"),
    toggle("generate_audio", "Audio", true),
  ];
}

function minimaxParams(includeAspect: boolean, aspectDefault = "16:9"): ParameterSpec[] {
  const params = [
    choice("duration", "Duration", minimaxDurations, "5", "stringToInt"),
    choice("resolution", "Resolution", ["768P", "2K", "4K"], "2K"),
  ];
  if (includeAspect) {
    const options =
      aspectDefault === "adaptive" ? ["adaptive", ...minimaxAspects] : minimaxAspects;
    params.push(choice("aspect_ratio", "Aspect", options, aspectDefault));
  }
  return params;
}

function klingParams(includeAspect: boolean): ParameterSpec[] {
  const params = [choice("duration", "Duration", klingDurations, "5")];
  if (includeAspect) {
    params.push(choice("aspect_ratio", "Aspect", ["16:9", "9:16", "1:1"], "16:9"));
  }
  params.push(toggle("generate_audio", "Audio", true));
  return params;
}

// MARK: Catalog

export const allSpecs: ModelSpec[] = [
  // ---- Images (sync fal.run) ----
  {
    id: "grok",
    displayName: "Grok Imagine v2",
    kind: "image",
    endpoint: "xai/grok-imagine-image/v2.0/text-to-image",
    queued: false,
    refImages: { type: "none" },
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("aspect_ratio", "Aspect", grokAspects, "16:9"),
      choice("resolution", "Resolution", ["1k", "2k"], "2k"),
      choice("quality", "Quality", ["low", "medium"], "medium"),
      stepper("num_images", "Images", 1, 4, 1),
    ],
    pricing: Pricing.grok,
  },
  {
    id: "grok-edit",
    displayName: "Grok Imagine v2 Edit",
    kind: "image",
    endpoint: "xai/grok-imagine-image/v2.0/edit",
    queued: false,
    refImages: { type: "multiple", max: 4 },
    refPayloadKey: "image_urls",
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("resolution", "Resolution", ["1k", "2k"], "2k"),
      choice("quality", "Quality", ["low", "medium"], "medium"),
      stepper("num_images", "Images", 1, 4, 1),
    ],
    pricing: Pricing.grok,
  },
  {
    id: "seedream",
    displayName: "Seedream 5.0 Pro",
    kind: "image",
    endpoint: "bytedance/seedream/v5/pro/text-to-image",
    queued: false,
    refImages: { type: "none" },
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("aspect_ratio", "Aspect", ["16:9", "9:16", "4:3", "3:4", "1:1"], "16:9", "seedreamImageSize"),
      stepper("num_images", "Images", 1, 6, 1),
    ],
    pricing: Pricing.seedream,
  },
  {
    id: "seedream-edit",
    displayName: "Seedream 5.0 Pro Edit",
    kind: "image",
    endpoint: "bytedance/seedream/v5/pro/edit",
    queued: false,
    refImages: { type: "multiple", max: 10 },
    refPayloadKey: "image_urls",
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("aspect_ratio", "Aspect", ["16:9", "9:16", "4:3", "3:4", "1:1"], "16:9", "seedreamImageSize"),
      stepper("num_images", "Images", 1, 6, 1),
    ],
    pricing: Pricing.seedream,
  },
  {
    id: "gpt-image",
    displayName: "GPT Image 2 (OpenAI)",
    kind: "image",
    endpoint: "openai/gpt-image-2",
    queued: false,
    refImages: { type: "none" },
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("aspect_ratio", "Aspect", ["auto", "16:9", "9:16", "4:3", "3:4", "1:1"], "auto", "seedreamImageSize"),
      choice("quality", "Quality", ["auto", "low", "medium", "high"], "high"),
      stepper("num_images", "Images", 1, 4, 1),
    ],
    pricing: Pricing.gptImage,
  },
  {
    id: "gpt-image-edit",
    displayName: "GPT Image 2 Edit (OpenAI)",
    kind: "image",
    endpoint: "openai/gpt-image-2/edit",
    queued: false,
    refImages: { type: "multiple", max: 16 },
    refPayloadKey: "image_urls",
    fixedPayload: { output_format: "png" },
    parameters: [
      choice("aspect_ratio", "Aspect", ["auto", "16:9", "9:16", "4:3", "3:4", "1:1"], "auto", "seedreamImageSize"),
      choice("quality", "Quality", ["auto", "low", "medium", "high"], "high"),
      stepper("num_images", "Images", 1, 4, 1),
    ],
    pricing: Pricing.gptImage,
  },

  // ---- Video: Seedance 2.5 (queue, up to 30 s) ----
  {
    id: "seedance-25",
    displayName: "Seedance 2.5",
    kind: "video",
    endpoint: "bytedance/seedance-2.5/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", seedance25Durations, "auto"),
      choice("aspect_ratio", "Aspect", seedanceAspects, "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.seedance25,
  },
  {
    id: "seedance-25-i2v",
    displayName: "Seedance 2.5 · Image to Video",
    kind: "video",
    endpoint: "bytedance/seedance-2.5/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", seedance25Durations, "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.seedance25,
  },

  // ---- Video: Seedance 2.0 (queue) ----
  {
    id: "seedance",
    displayName: "Seedance 2.0",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: seedanceParams(["480p", "720p"]),
    pricing: Pricing.seedance,
  },
  {
    id: "seedance-i2v",
    displayName: "Seedance 2.0 · Image to Video",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", seedanceDurations, "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.seedance,
  },
  {
    id: "seedance-ref",
    displayName: "Seedance 2.0 · Reference to Video",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/reference-to-video",
    queued: true,
    refImages: { type: "multiple", max: 9 },
    refPayloadKey: "image_urls",
    parameters: seedanceParams(["480p", "720p", "1080p", "4k"]),
    pricing: Pricing.seedance,
  },
  {
    id: "seedance-fast",
    displayName: "Seedance 2.0 Fast",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/fast/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: seedanceParams(["480p", "720p"]),
    pricing: Pricing.seedanceFast,
  },
  {
    id: "seedance-fast-i2v",
    displayName: "Seedance 2.0 Fast · Image to Video",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/fast/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", seedanceDurations, "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.seedanceFast,
  },
  {
    id: "seedance-fast-ref",
    displayName: "Seedance 2.0 Fast · Reference to Video",
    kind: "video",
    endpoint: "bytedance/seedance-2.0/fast/reference-to-video",
    queued: true,
    refImages: { type: "multiple", max: 9 },
    refPayloadKey: "image_urls",
    parameters: seedanceParams(["480p", "720p", "1080p", "4k"]),
    pricing: Pricing.seedanceFast,
  },

  // ---- Video: MiniMax H3 (queue) ----
  {
    id: "minimax",
    displayName: "MiniMax H3",
    kind: "video",
    endpoint: "minimax/h3/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: minimaxParams(true),
    pricing: Pricing.minimax,
  },
  {
    id: "minimax-i2v",
    displayName: "MiniMax H3 · Image to Video",
    kind: "video",
    endpoint: "minimax/h3/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: minimaxParams(false),
    pricing: Pricing.minimax,
  },
  {
    id: "minimax-ref",
    displayName: "MiniMax H3 · Reference to Video",
    kind: "video",
    endpoint: "minimax/h3/reference-to-video",
    queued: true,
    refImages: { type: "multiple", max: 9 },
    refPayloadKey: "reference_image_urls",
    parameters: minimaxParams(true, "adaptive"),
    pricing: Pricing.minimax,
  },

  // ---- Video: Kling v3 Pro (queue) ----
  {
    id: "kling",
    displayName: "Kling v3 Pro",
    kind: "video",
    endpoint: "fal-ai/kling-video/v3/pro/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: klingParams(true),
    pricing: Pricing.kling,
  },
  {
    id: "kling-i2v",
    displayName: "Kling v3 Pro · Image to Video",
    kind: "video",
    endpoint: "fal-ai/kling-video/v3/pro/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "start_image_url",
    endImagePayloadKey: "end_image_url",
    parameters: klingParams(false),
    pricing: Pricing.kling,
  },

  // ---- Video: Grok Imagine Video 1.5 (queue) ----
  {
    id: "grok-video",
    displayName: "Grok Imagine Video",
    kind: "video",
    endpoint: "xai/grok-imagine-video/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", range(6, 15), "6", "stringToInt"),
      choice("aspect_ratio", "Aspect", ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3"], "16:9"),
    ],
    pricing: Pricing.grokVideo,
  },
  {
    id: "grok-video-i2v",
    displayName: "Grok Imagine Video · Image to Video",
    kind: "video",
    endpoint: "xai/grok-imagine-video/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    parameters: [
      choice("resolution", "Resolution", ["480p", "720p"], "720p"),
      choice("duration", "Duration", range(6, 15), "6", "stringToInt"),
    ],
    pricing: Pricing.grokVideo,
  },

  // ---- Video: Wan 2.7 (queue) ----
  {
    id: "wan",
    displayName: "Wan 2.7",
    kind: "video",
    endpoint: "fal-ai/wan/v2.7/text-to-video",
    queued: true,
    refImages: { type: "none" },
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p"], "1080p"),
      choice("duration", "Duration", range(2, 15), "5", "stringToInt"),
      choice("aspect_ratio", "Aspect", ["16:9", "9:16", "1:1", "4:3", "3:4"], "16:9"),
    ],
    pricing: Pricing.wan,
  },
  {
    id: "wan-i2v",
    displayName: "Wan 2.7 · Image to Video",
    kind: "video",
    endpoint: "fal-ai/wan/v2.7/image-to-video",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p"], "1080p"),
      choice("duration", "Duration", range(2, 15), "5", "stringToInt"),
    ],
    pricing: Pricing.wan,
  },

  // ---- Video: LTX-2.5 (Lightricks, queue) ----
  {
    id: "ltx-pro",
    displayName: "LTX-2.5 Pro",
    kind: "video",
    endpoint: "lightricks/ltx-2.5/text-to-video/pro",
    queued: true,
    refImages: { type: "none" },
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p"], "720p"),
      choice("duration", "Duration", ["auto", "6", "8", "10"], "auto"),
      choice("aspect_ratio", "Aspect", ["16:9", "9:16"], "16:9"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.ltxPro,
  },
  {
    id: "ltx-pro-i2v",
    displayName: "LTX-2.5 Pro · Image to Video",
    kind: "video",
    endpoint: "lightricks/ltx-2.5/image-to-video/pro",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p"], "720p"),
      choice("duration", "Duration", ["auto", "6", "8", "10"], "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.ltxPro,
  },
  {
    id: "ltx-fast",
    displayName: "LTX-2.5 Fast",
    kind: "video",
    endpoint: "lightricks/ltx-2.5/text-to-video/fast",
    queued: true,
    refImages: { type: "none" },
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p", "1440p", "4k"], "720p"),
      choice("duration", "Duration", ["auto", "6", "8", "10", "12", "14", "16", "18", "20"], "auto"),
      choice("aspect_ratio", "Aspect", ["16:9", "9:16"], "16:9"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.ltxFast,
  },
  {
    id: "ltx-fast-i2v",
    displayName: "LTX-2.5 Fast · Image to Video",
    kind: "video",
    endpoint: "lightricks/ltx-2.5/image-to-video/fast",
    queued: true,
    refImages: { type: "startEnd" },
    refPayloadKey: "image_url",
    endImagePayloadKey: "end_image_url",
    parameters: [
      choice("resolution", "Resolution", ["720p", "1080p", "1440p", "4k"], "720p"),
      choice("duration", "Duration", ["auto", "6", "8", "10", "12", "14", "16", "18", "20"], "auto"),
      toggle("generate_audio", "Audio", true),
    ],
    pricing: Pricing.ltxFast,
  },
];

export function modelsFor(kind: MediaKind): ModelSpec[] {
  return allSpecs.filter((s) => s.kind === kind);
}

export function specFor(id: string): ModelSpec | undefined {
  return allSpecs.find((s) => s.id === id);
}

export function defaultModelID(kind: MediaKind): string {
  return kind === "image" ? "grok" : "seedance";
}

// MARK: Families — one picker entry per model; the endpoint variant
// (text-to-x / image-to-video / edit / reference) resolves automatically
// from the reference images the user provides.

export const families: ModelFamily[] = [
  { id: "fam-grok", displayName: "Grok Imagine v2", kind: "image", baseSpecID: "grok", multipleSpecID: "grok-edit" },
  { id: "fam-seedream", displayName: "Seedream 5.0 Pro", kind: "image", baseSpecID: "seedream", multipleSpecID: "seedream-edit" },
  { id: "fam-gpt", displayName: "GPT Image 2 (ChatGPT)", kind: "image", baseSpecID: "gpt-image", multipleSpecID: "gpt-image-edit" },
  { id: "fam-seedance25", displayName: "Seedance 2.5", kind: "video", baseSpecID: "seedance-25", startEndSpecID: "seedance-25-i2v" },
  { id: "fam-seedance", displayName: "Seedance 2.0", kind: "video", baseSpecID: "seedance", startEndSpecID: "seedance-i2v", multipleSpecID: "seedance-ref" },
  { id: "fam-seedance-fast", displayName: "Seedance 2.0 Fast", kind: "video", baseSpecID: "seedance-fast", startEndSpecID: "seedance-fast-i2v", multipleSpecID: "seedance-fast-ref" },
  { id: "fam-minimax", displayName: "MiniMax H3", kind: "video", baseSpecID: "minimax", startEndSpecID: "minimax-i2v", multipleSpecID: "minimax-ref" },
  { id: "fam-kling", displayName: "Kling v3 Pro", kind: "video", baseSpecID: "kling", startEndSpecID: "kling-i2v" },
  { id: "fam-grok-video", displayName: "Grok Imagine Video", kind: "video", baseSpecID: "grok-video", startEndSpecID: "grok-video-i2v" },
  { id: "fam-wan", displayName: "Wan 2.7", kind: "video", baseSpecID: "wan", startEndSpecID: "wan-i2v" },
  { id: "fam-ltx-pro", displayName: "LTX-2.5 Pro", kind: "video", baseSpecID: "ltx-pro", startEndSpecID: "ltx-pro-i2v" },
  { id: "fam-ltx-fast", displayName: "LTX-2.5 Fast", kind: "video", baseSpecID: "ltx-fast", startEndSpecID: "ltx-fast-i2v" },
];

export function familyFor(id: string): ModelFamily | undefined {
  return families.find((f) => f.id === id);
}

/** Map a concrete spec id (e.g. "seedance-i2v" from an old gallery item)
 *  back to its family for the picker. */
export function familyIDForSpecID(specID: string): string | undefined {
  return families.find(
    (f) => f.baseSpecID === specID || f.startEndSpecID === specID || f.multipleSpecID === specID
  )?.id;
}

export function defaultFamilyID(kind: MediaKind): string {
  return kind === "image" ? "fam-grok" : "fam-seedance";
}
