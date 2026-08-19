// Port of Sources/Models/PayloadBuilder.swift — builds the FAL request payload
// from a model spec, UI parameter values, and pre-encoded reference-image
// data URIs.

import { JSONValue, ModelSpec, paramDefaultValue } from "./types";

export function buildPayload(
  spec: ModelSpec,
  prompt: string,
  values: Record<string, JSONValue>,
  refDataURIs: string[],
  endImageDataURI: string | null
): Record<string, JSONValue> {
  const payload: Record<string, JSONValue> = { ...(spec.fixedPayload ?? {}) };
  payload.prompt = prompt;

  for (const param of spec.parameters) {
    const value = values[param.key] ?? paramDefaultValue(param);
    switch (param.encoding ?? "raw") {
      case "raw":
        payload[param.key] = value;
        break;
      case "stringToInt": {
        if (typeof value === "string" && /^\d+$/.test(value)) {
          payload[param.key] = parseInt(value, 10);
        } else {
          payload[param.key] = value;
        }
        break;
      }
      case "seedreamImageSize": {
        if (typeof value === "string") {
          payload.image_size = seedreamImageSize(value);
        }
        break;
      }
    }
  }

  if (spec.refPayloadKey && refDataURIs.length > 0) {
    if (spec.refImages.type === "multiple") {
      payload[spec.refPayloadKey] = refDataURIs;
    } else {
      payload[spec.refPayloadKey] = refDataURIs[0];
    }
  }
  if (spec.endImagePayloadKey && endImageDataURI) {
    payload[spec.endImagePayloadKey] = endImageDataURI;
  }
  return payload;
}

/** Known ratios map to presets, anything else becomes a custom size with
 *  longest edge 2048 (min edge 1024). GPT Image 2 uses the same preset names
 *  and additionally accepts "auto". */
export function seedreamImageSize(aspect: string): JSONValue {
  if (aspect === "auto") return "auto";
  const presets: Record<string, string> = {
    "16:9": "landscape_16_9",
    "9:16": "portrait_16_9",
    "4:3": "landscape_4_3",
    "3:4": "portrait_4_3",
    "1:1": "square_hd",
  };
  const preset = presets[aspect];
  if (preset) return preset;
  const parts = aspect.split(":").map(Number).filter((n) => Number.isFinite(n));
  if (parts.length !== 2 || parts[0] <= 0 || parts[1] <= 0) {
    return "landscape_16_9";
  }
  const [wr, hr] = parts;
  let w = 2048;
  let h = 2048;
  if (wr >= hr) {
    h = Math.trunc((2048 * hr) / wr);
  } else {
    w = Math.trunc((2048 * wr) / hr);
  }
  return { width: Math.max(w, 1024), height: Math.max(h, 1024) };
}
