import Foundation

nonisolated enum PricingRule: Sendable {
    /// Cost per generated image, keyed by the "resolution" parameter; multiplied by num_images.
    case perImage(byResolution: [String: Double], base: Double)
    /// Cost per second of video, keyed by "resolution"; "auto" duration assumes `autoDurationAssumption`.
    case perSecond(byResolution: [String: Double], base: Double,
                   audioSurcharge: Double?, autoDurationAssumption: Double)
    /// Fixed user-supplied estimate per generation (custom models).
    case flat(Double)
}

nonisolated enum Pricing {
    // Sources: fal.ai model pages (Aug 2026). Video rates for Seedance are derived from
    // fal's published 720p rates and its token pricing (tokens scale with pixel count),
    // so non-720p tiers are estimates. TODO verify at https://fal.ai/models/<endpoint>
    static let grok = PricingRule.perImage(
        byResolution: ["1k": 0.035, "2k": 0.07], base: 0.07)
    static let seedream = PricingRule.perImage(
        byResolution: [:], base: 0.135)   // longest edge 2048 tier
    static let seedance = PricingRule.perSecond(
        byResolution: ["480p": 0.135, "720p": 0.3034, "1080p": 0.68, "4k": 2.70],
        base: 0.3034, audioSurcharge: nil, autoDurationAssumption: 5)
    static let seedanceFast = PricingRule.perSecond(
        byResolution: ["480p": 0.108, "720p": 0.2419, "1080p": 0.54, "4k": 2.15],
        base: 0.2419, audioSurcharge: nil, autoDurationAssumption: 5)
    static let minimax = PricingRule.perSecond(
        byResolution: ["768P": 0.10, "2K": 0.26, "4K": 0.52],
        base: 0.26, audioSurcharge: nil, autoDurationAssumption: 5)
    static let kling = PricingRule.perSecond(
        byResolution: [:], base: 0.112,
        audioSurcharge: 0.056, autoDurationAssumption: 5)

    /// Estimated cost in USD for the current draft values (pre-encoding UI values).
    static func estimate(spec: ModelSpec, values: [String: JSONValue]) -> Double {
        func value(_ key: String) -> JSONValue? {
            values[key] ?? spec.parameters.first { $0.key == key }?.defaultValue
        }
        switch spec.pricing {
        case .flat(let cost):
            return cost
        case .perImage(let byResolution, let base):
            let rate = value("resolution")?.stringValue.flatMap { byResolution[$0] } ?? base
            let count = value("num_images")?.intValue ?? 1
            return rate * Double(count)
        case .perSecond(let byResolution, let base, let audioSurcharge, let autoAssumption):
            var rate = value("resolution")?.stringValue.flatMap { byResolution[$0] } ?? base
            if let surcharge = audioSurcharge, value("generate_audio")?.boolValue == true {
                rate += surcharge
            }
            let duration: Double
            switch value("duration") {
            case .some(.string(let s)): duration = Double(s) ?? autoAssumption
            case .some(.int(let i)): duration = Double(i)
            default: duration = autoAssumption
            }
            return rate * duration
        }
    }
}
