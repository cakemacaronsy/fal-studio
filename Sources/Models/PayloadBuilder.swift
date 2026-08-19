import Foundation

/// Builds the FAL request payload from a model spec, UI parameter values,
/// and pre-encoded reference-image data URIs. Mirrors the payload shapes of
/// the fal skill's fal_generate.py / fal_video.py scripts.
nonisolated enum PayloadBuilder {
    static func build(spec: ModelSpec,
                      prompt: String,
                      values: [String: JSONValue],
                      refDataURIs: [String],
                      endImageDataURI: String?) -> [String: JSONValue] {
        var payload = spec.fixedPayload
        payload["prompt"] = .string(prompt)

        for param in spec.parameters {
            let value = values[param.key] ?? param.defaultValue
            switch param.encoding {
            case .raw:
                payload[param.key] = value
            case .stringToInt:
                if let s = value.stringValue, let i = Int(s) {
                    payload[param.key] = .int(i)
                } else {
                    payload[param.key] = value
                }
            case .seedreamImageSize:
                if let aspect = value.stringValue {
                    payload["image_size"] = seedreamImageSize(aspect: aspect)
                }
            }
        }

        if let refKey = spec.refPayloadKey, !refDataURIs.isEmpty {
            switch spec.refImages {
            case .multiple:
                payload[refKey] = .array(refDataURIs.map { .string($0) })
            case .startEnd, .none:
                payload[refKey] = .string(refDataURIs[0])
            }
        }
        if let endKey = spec.endImagePayloadKey, let end = endImageDataURI {
            payload[endKey] = .string(end)
        }
        return payload
    }

    /// Port of fal_generate.py seedream_image_size(): known ratios map to presets,
    /// anything else becomes a custom size with longest edge 2048 (min edge 1024).
    /// GPT Image 2 uses the same preset names and additionally accepts "auto".
    static func seedreamImageSize(aspect: String) -> JSONValue {
        if aspect == "auto" {
            return .string("auto")
        }
        let presets: [String: String] = [
            "16:9": "landscape_16_9",
            "9:16": "portrait_16_9",
            "4:3": "landscape_4_3",
            "3:4": "portrait_4_3",
            "1:1": "square_hd",
        ]
        if let preset = presets[aspect] {
            return .string(preset)
        }
        let parts = aspect.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return .string("landscape_16_9")
        }
        let (wr, hr) = (parts[0], parts[1])
        var w = 2048, h = 2048
        if wr >= hr {
            h = Int(2048 * hr / wr)
        } else {
            w = Int(2048 * wr / hr)
        }
        return .object(["width": .int(max(w, 1024)), "height": .int(max(h, 1024))])
    }
}
