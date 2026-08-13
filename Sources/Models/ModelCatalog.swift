import Foundation

nonisolated enum MediaKind: String, Codable, Sendable {
    case image, video
}

/// What kind of reference-image input a model accepts.
nonisolated enum RefImageSupport: Equatable, Sendable {
    case none
    /// A start frame plus an optional end frame (image-to-video models).
    case startEnd
    /// Multiple reference images up to `max` (edit / reference-to-video models).
    case multiple(max: Int)
}

nonisolated enum ParamKind: Sendable {
    case choice(options: [String], defaultValue: String)
    case toggle(defaultValue: Bool)
    case stepper(range: ClosedRange<Int>, defaultValue: Int)
}

nonisolated enum ParamEncoding: Sendable {
    case raw
    /// UI string → Int in the payload (MiniMax duration).
    case stringToInt
    /// Aspect-ratio string → Seedream `image_size` preset/object; key becomes "image_size".
    case seedreamImageSize
}

nonisolated struct ParameterSpec: Identifiable, Sendable {
    let key: String        // payload key ("aspect_ratio", "resolution", ...)
    let label: String      // chip label
    let kind: ParamKind
    var encoding: ParamEncoding = .raw
    var id: String { key }

    var defaultValue: JSONValue {
        switch kind {
        case .choice(_, let d): return .string(d)
        case .toggle(let d): return .bool(d)
        case .stepper(_, let d): return .int(d)
        }
    }
}

nonisolated struct ModelSpec: Identifiable, Sendable {
    let id: String
    let displayName: String
    let kind: MediaKind
    let endpoint: String          // path after fal.run / queue.fal.run
    let queued: Bool              // true → queue API (video)
    var refImages: RefImageSupport = .none
    var refPayloadKey: String? = nil        // "image_urls" / "image_url" / "start_image_url" / "reference_image_urls"
    var endImagePayloadKey: String? = nil   // "end_image_url"
    var fixedPayload: [String: JSONValue] = [:]
    let parameters: [ParameterSpec]
    let pricing: PricingRule
}

nonisolated enum ModelCatalog {
    // MARK: Shared option lists

    private static let grokAspects = [
        "2:1", "20:9", "19.5:9", "16:9", "3:2", "4:3", "1:1",
        "3:4", "2:3", "9:16", "9:19.5", "9:20", "1:2",
    ]
    private static let seedanceAspects = ["auto", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"]
    private static let seedanceDurations = ["auto"] + (4...15).map(String.init)
    private static let minimaxAspects = ["16:9", "21:9", "4:3", "1:1", "3:4", "9:16"]
    private static let minimaxDurations = (5...15).map(String.init)
    private static let klingDurations = (3...15).map(String.init)

    private static func seedanceParams(resolutions: [String]) -> [ParameterSpec] {
        [
            ParameterSpec(key: "resolution", label: "Resolution",
                          kind: .choice(options: resolutions, defaultValue: "720p")),
            ParameterSpec(key: "duration", label: "Duration",
                          kind: .choice(options: seedanceDurations, defaultValue: "auto")),
            ParameterSpec(key: "aspect_ratio", label: "Aspect",
                          kind: .choice(options: seedanceAspects, defaultValue: "auto")),
            ParameterSpec(key: "generate_audio", label: "Audio", kind: .toggle(defaultValue: true)),
        ]
    }

    private static func minimaxParams(includeAspect: Bool, aspectDefault: String = "16:9") -> [ParameterSpec] {
        var params = [
            ParameterSpec(key: "duration", label: "Duration",
                          kind: .choice(options: minimaxDurations, defaultValue: "5"),
                          encoding: .stringToInt),
            ParameterSpec(key: "resolution", label: "Resolution",
                          kind: .choice(options: ["768P", "2K", "4K"], defaultValue: "2K")),
        ]
        if includeAspect {
            let options = aspectDefault == "adaptive" ? ["adaptive"] + minimaxAspects : minimaxAspects
            params.append(ParameterSpec(key: "aspect_ratio", label: "Aspect",
                                        kind: .choice(options: options, defaultValue: aspectDefault)))
        }
        return params
    }

    private static func klingParams(includeAspect: Bool) -> [ParameterSpec] {
        var params = [
            ParameterSpec(key: "duration", label: "Duration",
                          kind: .choice(options: klingDurations, defaultValue: "5")),
        ]
        if includeAspect {
            params.append(ParameterSpec(key: "aspect_ratio", label: "Aspect",
                                        kind: .choice(options: ["16:9", "9:16", "1:1"], defaultValue: "16:9")))
        }
        params.append(ParameterSpec(key: "generate_audio", label: "Audio", kind: .toggle(defaultValue: true)))
        return params
    }

    // MARK: Catalog

    static let all: [ModelSpec] = [
        // ---- Images (sync fal.run) ----
        ModelSpec(
            id: "grok", displayName: "Grok Imagine v2",
            kind: .image, endpoint: "xai/grok-imagine-image/v2.0/text-to-image", queued: false,
            fixedPayload: ["output_format": .string("png")],
            parameters: [
                ParameterSpec(key: "aspect_ratio", label: "Aspect",
                              kind: .choice(options: grokAspects, defaultValue: "16:9")),
                ParameterSpec(key: "resolution", label: "Resolution",
                              kind: .choice(options: ["1k", "2k"], defaultValue: "2k")),
                ParameterSpec(key: "quality", label: "Quality",
                              kind: .choice(options: ["low", "medium"], defaultValue: "medium")),
                ParameterSpec(key: "num_images", label: "Images", kind: .stepper(range: 1...4, defaultValue: 1)),
            ],
            pricing: Pricing.grok
        ),
        ModelSpec(
            id: "grok-edit", displayName: "Grok Imagine v2 Edit",
            kind: .image, endpoint: "xai/grok-imagine-image/v2.0/edit", queued: false,
            refImages: .multiple(max: 4), refPayloadKey: "image_urls",
            fixedPayload: ["output_format": .string("png")],
            parameters: [
                ParameterSpec(key: "resolution", label: "Resolution",
                              kind: .choice(options: ["1k", "2k"], defaultValue: "2k")),
                ParameterSpec(key: "quality", label: "Quality",
                              kind: .choice(options: ["low", "medium"], defaultValue: "medium")),
                ParameterSpec(key: "num_images", label: "Images", kind: .stepper(range: 1...4, defaultValue: 1)),
            ],
            pricing: Pricing.grok
        ),
        ModelSpec(
            id: "seedream", displayName: "Seedream 5.0 Pro",
            kind: .image, endpoint: "bytedance/seedream/v5/pro/text-to-image", queued: false,
            fixedPayload: ["output_format": .string("png")],
            parameters: [
                ParameterSpec(key: "aspect_ratio", label: "Aspect",
                              kind: .choice(options: ["16:9", "9:16", "4:3", "3:4", "1:1"], defaultValue: "16:9"),
                              encoding: .seedreamImageSize),
                ParameterSpec(key: "num_images", label: "Images", kind: .stepper(range: 1...6, defaultValue: 1)),
            ],
            pricing: Pricing.seedream
        ),
        ModelSpec(
            id: "seedream-edit", displayName: "Seedream 5.0 Pro Edit",
            kind: .image, endpoint: "bytedance/seedream/v5/pro/edit", queued: false,
            refImages: .multiple(max: 10), refPayloadKey: "image_urls",
            fixedPayload: ["output_format": .string("png")],
            parameters: [
                ParameterSpec(key: "aspect_ratio", label: "Aspect",
                              kind: .choice(options: ["16:9", "9:16", "4:3", "3:4", "1:1"], defaultValue: "16:9"),
                              encoding: .seedreamImageSize),
                ParameterSpec(key: "num_images", label: "Images", kind: .stepper(range: 1...6, defaultValue: 1)),
            ],
            pricing: Pricing.seedream
        ),

        // ---- Video: Seedance 2.0 (queue) ----
        ModelSpec(
            id: "seedance", displayName: "Seedance 2.0",
            kind: .video, endpoint: "bytedance/seedance-2.0/text-to-video", queued: true,
            parameters: seedanceParams(resolutions: ["480p", "720p"]),
            pricing: Pricing.seedance
        ),
        ModelSpec(
            id: "seedance-i2v", displayName: "Seedance 2.0 · Image to Video",
            kind: .video, endpoint: "bytedance/seedance-2.0/image-to-video", queued: true,
            refImages: .startEnd, refPayloadKey: "image_url", endImagePayloadKey: "end_image_url",
            parameters: [
                ParameterSpec(key: "resolution", label: "Resolution",
                              kind: .choice(options: ["480p", "720p"], defaultValue: "720p")),
                ParameterSpec(key: "duration", label: "Duration",
                              kind: .choice(options: seedanceDurations, defaultValue: "auto")),
                ParameterSpec(key: "generate_audio", label: "Audio", kind: .toggle(defaultValue: true)),
            ],
            pricing: Pricing.seedance
        ),
        ModelSpec(
            id: "seedance-ref", displayName: "Seedance 2.0 · Reference to Video",
            kind: .video, endpoint: "bytedance/seedance-2.0/reference-to-video", queued: true,
            refImages: .multiple(max: 9), refPayloadKey: "image_urls",
            parameters: seedanceParams(resolutions: ["480p", "720p", "1080p", "4k"]),
            pricing: Pricing.seedance
        ),
        ModelSpec(
            id: "seedance-fast", displayName: "Seedance 2.0 Fast",
            kind: .video, endpoint: "bytedance/seedance-2.0/fast/text-to-video", queued: true,
            parameters: seedanceParams(resolutions: ["480p", "720p"]),
            pricing: Pricing.seedanceFast
        ),
        ModelSpec(
            id: "seedance-fast-i2v", displayName: "Seedance 2.0 Fast · Image to Video",
            kind: .video, endpoint: "bytedance/seedance-2.0/fast/image-to-video", queued: true,
            refImages: .startEnd, refPayloadKey: "image_url", endImagePayloadKey: "end_image_url",
            parameters: [
                ParameterSpec(key: "resolution", label: "Resolution",
                              kind: .choice(options: ["480p", "720p"], defaultValue: "720p")),
                ParameterSpec(key: "duration", label: "Duration",
                              kind: .choice(options: seedanceDurations, defaultValue: "auto")),
                ParameterSpec(key: "generate_audio", label: "Audio", kind: .toggle(defaultValue: true)),
            ],
            pricing: Pricing.seedanceFast
        ),
        ModelSpec(
            id: "seedance-fast-ref", displayName: "Seedance 2.0 Fast · Reference to Video",
            kind: .video, endpoint: "bytedance/seedance-2.0/fast/reference-to-video", queued: true,
            refImages: .multiple(max: 9), refPayloadKey: "image_urls",
            parameters: seedanceParams(resolutions: ["480p", "720p", "1080p", "4k"]),
            pricing: Pricing.seedanceFast
        ),

        // ---- Video: MiniMax H3 (queue) ----
        ModelSpec(
            id: "minimax", displayName: "MiniMax H3",
            kind: .video, endpoint: "minimax/h3/text-to-video", queued: true,
            parameters: minimaxParams(includeAspect: true),
            pricing: Pricing.minimax
        ),
        ModelSpec(
            id: "minimax-i2v", displayName: "MiniMax H3 · Image to Video",
            kind: .video, endpoint: "minimax/h3/image-to-video", queued: true,
            refImages: .startEnd, refPayloadKey: "image_url", endImagePayloadKey: "end_image_url",
            parameters: minimaxParams(includeAspect: false),
            pricing: Pricing.minimax
        ),
        ModelSpec(
            id: "minimax-ref", displayName: "MiniMax H3 · Reference to Video",
            kind: .video, endpoint: "minimax/h3/reference-to-video", queued: true,
            refImages: .multiple(max: 9), refPayloadKey: "reference_image_urls",
            parameters: minimaxParams(includeAspect: true, aspectDefault: "adaptive"),
            pricing: Pricing.minimax
        ),

        // ---- Video: Kling v3 Pro (queue) ----
        ModelSpec(
            id: "kling", displayName: "Kling v3 Pro",
            kind: .video, endpoint: "fal-ai/kling-video/v3/pro/text-to-video", queued: true,
            parameters: klingParams(includeAspect: true),
            pricing: Pricing.kling
        ),
        ModelSpec(
            id: "kling-i2v", displayName: "Kling v3 Pro · Image to Video",
            kind: .video, endpoint: "fal-ai/kling-video/v3/pro/image-to-video", queued: true,
            refImages: .startEnd, refPayloadKey: "start_image_url", endImagePayloadKey: "end_image_url",
            parameters: klingParams(includeAspect: false),
            pricing: Pricing.kling
        ),
    ]

    static func models(for kind: MediaKind) -> [ModelSpec] {
        all.filter { $0.kind == kind }
    }

    static func spec(for id: String) -> ModelSpec? {
        all.first { $0.id == id }
    }

    static func defaultModelID(for kind: MediaKind) -> String {
        kind == .image ? "grok" : "seedance"
    }
}
