import Foundation
import Observation

/// A user-registered fal.ai endpoint (Settings → Models). Uses the same API
/// key and billing as the built-in models.
nonisolated struct CustomModel: Identifiable, Codable, Hashable, Sendable {
    enum RefMode: String, Codable, CaseIterable, Sendable {
        case none, startEnd, multiple
    }

    var id = UUID()
    var displayName: String = ""
    var kind: MediaKind = .video
    var endpoint: String = ""            // path after fal.run / queue.fal.run
    var queued: Bool = true              // video → queue API
    var refMode: RefMode = .none
    var refMax: Int = 4                  // for .multiple
    var refPayloadKey: String = "image_url"
    var acceptsEndImage: Bool = false    // .startEnd only → end_image_url
    var fixedParamsJSON: String = ""     // JSON object merged into the payload
    var estCost: Double = 0              // shown as the ~$ estimate

    static let refKeyOptions = ["image_url", "image_urls", "start_image_url", "reference_image_urls"]

    /// The model-picker id; prefixed so it can never collide with catalog ids.
    var specID: String { "custom-\(id.uuidString)" }

    var fixedPayload: [String: JSONValue]? {
        let trimmed = fixedParamsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return nil
        }
        return dict
    }

    func toSpec() -> ModelSpec? {
        guard let fixed = fixedPayload, !endpoint.isEmpty else { return nil }
        let refSupport: RefImageSupport
        switch refMode {
        case .none: refSupport = .none
        case .startEnd: refSupport = .startEnd
        case .multiple: refSupport = .multiple(max: max(1, refMax))
        }
        return ModelSpec(
            id: specID,
            displayName: displayName.isEmpty ? endpoint : displayName,
            kind: kind,
            endpoint: endpoint,
            queued: queued,
            refImages: refSupport,
            refPayloadKey: refMode == .none ? nil : refPayloadKey,
            endImagePayloadKey: (refMode == .startEnd && acceptsEndImage) ? "end_image_url" : nil,
            fixedPayload: fixed,
            parameters: [],          // custom models have no chips in v1
            pricing: .flat(estCost)
        )
    }

    /// Strip a pasted URL down to the endpoint path fal expects.
    static func normalizeEndpoint(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://queue.fal.run/", "https://fal.run/",
                       "queue.fal.run/", "fal.run/",
                       "https://fal.ai/models/", "fal.ai/models/"] {
            if path.lowercased().hasPrefix(prefix) {
                path = String(path.dropFirst(prefix.count))
                break
            }
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

nonisolated struct ModelChoice: Identifiable, Sendable {
    let id: String
    let displayName: String
}

/// Merges the static catalog with the user's custom models and persists the
/// custom list to Application Support/FAL Studio/custom_models.json.
@Observable
final class ModelStore {
    static let shared = ModelStore()

    private(set) var customModels: [CustomModel] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("FAL Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("custom_models.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([CustomModel].self, from: data) {
            customModels = loaded
        }
    }

    func models(for kind: MediaKind) -> [ModelSpec] {
        ModelCatalog.models(for: kind) + customModels
            .filter { $0.kind == kind }
            .compactMap { $0.toSpec() }
    }

    /// Picker entries: ONE per model family (variant endpoints resolve from
    /// the provided reference images), plus the user's custom models.
    func choices(for kind: MediaKind) -> [ModelChoice] {
        ModelCatalog.families
            .filter { $0.kind == kind }
            .map { ModelChoice(id: $0.id, displayName: $0.displayName) }
        + customModels
            .filter { $0.kind == kind }
            .map { ModelChoice(id: $0.specID,
                               displayName: $0.displayName.isEmpty ? $0.endpoint : $0.displayName) }
    }

    func spec(for id: String) -> ModelSpec? {
        ModelCatalog.spec(for: id)
            ?? customModels.first { $0.specID == id }?.toSpec()
    }

    func customModel(specID: String) -> CustomModel? {
        customModels.first { $0.specID == specID }
    }

    func upsert(_ model: CustomModel) {
        if let index = customModels.firstIndex(where: { $0.id == model.id }) {
            customModels[index] = model
        } else {
            customModels.append(model)
        }
        persist()
    }

    func delete(_ model: CustomModel) {
        customModels.removeAll { $0.id == model.id }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(customModels) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
