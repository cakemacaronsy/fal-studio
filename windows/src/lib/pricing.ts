// Port of Sources/Models/Pricing.swift.
// Sources: fal.ai model pages (Aug 2026). Video rates for Seedance are derived
// from fal's published 720p rates and its token pricing, so non-720p tiers are
// estimates.

import {
  JSONValue,
  ModelSpec,
  PricingRule,
  paramDefaultValue,
  stringValue,
  intValue,
  boolValue,
} from "./types";

export const Pricing = {
  grok: {
    type: "perImage",
    byResolution: { "1k": 0.035, "2k": 0.07 },
    base: 0.07,
  } as PricingRule,
  seedream: {
    type: "perImage",
    byResolution: {},
    base: 0.135, // longest edge 2048 tier
  } as PricingRule,
  // GPT Image 2 prices by quality tier (fal: $0.01 low → $0.41 high@4K);
  // estimate() falls back to the "quality" parameter when a model has no
  // "resolution".
  gptImage: {
    type: "perImage",
    byResolution: { low: 0.013, medium: 0.05, high: 0.17, auto: 0.17 },
    base: 0.17,
  } as PricingRule,
  // Seedance 2.5 (fal, Aug 2026): 480p ~$0.2205/s, 720p ~$0.4730/s
  seedance25: {
    type: "perSecond",
    byResolution: { "480p": 0.2205, "720p": 0.473 },
    base: 0.473,
    audioSurcharge: null,
    autoDurationAssumption: 5,
  } as PricingRule,
  seedance: {
    type: "perSecond",
    byResolution: { "480p": 0.135, "720p": 0.3034, "1080p": 0.68, "4k": 2.7 },
    base: 0.3034,
    audioSurcharge: null,
    autoDurationAssumption: 5,
  } as PricingRule,
  seedanceFast: {
    type: "perSecond",
    byResolution: { "480p": 0.108, "720p": 0.2419, "1080p": 0.54, "4k": 2.15 },
    base: 0.2419,
    audioSurcharge: null,
    autoDurationAssumption: 5,
  } as PricingRule,
  minimax: {
    type: "perSecond",
    byResolution: { "768P": 0.1, "2K": 0.26, "4K": 0.52 },
    base: 0.26,
    audioSurcharge: null,
    autoDurationAssumption: 5,
  } as PricingRule,
  kling: {
    type: "perSecond",
    byResolution: {},
    base: 0.112,
    audioSurcharge: 0.056,
    autoDurationAssumption: 5,
  } as PricingRule,
  // Grok Imagine Video 1.5 (fal): $0.05/s
  grokVideo: {
    type: "perSecond",
    byResolution: {},
    base: 0.05,
    audioSurcharge: null,
    autoDurationAssumption: 6,
  } as PricingRule,
  // Wan 2.7 (fal): ~$0.10/s at 720p; 1080p estimated ×2.
  wan: {
    type: "perSecond",
    byResolution: { "720p": 0.1, "1080p": 0.2 },
    base: 0.2,
    audioSurcharge: null,
    autoDurationAssumption: 5,
  } as PricingRule,
  // LTX-2.5 (fal, Aug 2026): Pro $0.12/s 720p, $0.17/s 1080p;
  // Fast $0.09/s 720p, $0.13/s 1080p, $0.19/s 1440p, $0.30/s 4k
  ltxPro: {
    type: "perSecond",
    byResolution: { "720p": 0.12, "1080p": 0.17 },
    base: 0.12,
    audioSurcharge: null,
    autoDurationAssumption: 6,
  } as PricingRule,
  ltxFast: {
    type: "perSecond",
    byResolution: { "720p": 0.09, "1080p": 0.13, "1440p": 0.19, "4k": 0.3 },
    base: 0.09,
    audioSurcharge: null,
    autoDurationAssumption: 6,
  } as PricingRule,
};

/** Estimated cost in USD for the current draft values (pre-encoding UI values). */
export function estimateCost(
  spec: ModelSpec,
  values: Record<string, JSONValue>
): number {
  const value = (key: string): JSONValue | undefined => {
    if (values[key] !== undefined) return values[key];
    const param = spec.parameters.find((p) => p.key === key);
    return param ? paramDefaultValue(param) : undefined;
  };

  const rule = spec.pricing;
  switch (rule.type) {
    case "flat":
      return rule.cost;
    case "perImage": {
      const tier = stringValue(value("resolution")) ?? stringValue(value("quality"));
      const rate = (tier !== null ? rule.byResolution[tier] : undefined) ?? rule.base;
      const count = intValue(value("num_images")) ?? 1;
      return rate * count;
    }
    case "perSecond": {
      const tier = stringValue(value("resolution"));
      let rate = (tier !== null ? rule.byResolution[tier] : undefined) ?? rule.base;
      if (rule.audioSurcharge !== null && boolValue(value("generate_audio")) === true) {
        rate += rule.audioSurcharge;
      }
      const durationValue = value("duration");
      let duration: number;
      if (typeof durationValue === "string") {
        const parsed = Number(durationValue);
        duration = Number.isFinite(parsed) ? parsed : rule.autoDurationAssumption;
      } else if (typeof durationValue === "number") {
        duration = durationValue;
      } else {
        duration = rule.autoDurationAssumption;
      }
      return rate * duration;
    }
  }
}
