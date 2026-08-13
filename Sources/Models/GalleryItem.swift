import Foundation

nonisolated enum ItemStatus: Codable, Hashable, Sendable {
    case generating
    case completed
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// One work on the gallery wall. Persisted in library.json; media files live alongside it.
nonisolated struct GalleryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    var fileName: String?           // media/<id>.png|.mp4, nil while generating
    var thumbnailFileName: String?  // thumbnails/<id>.jpg
    let prompt: String
    let modelID: String
    let endpoint: String
    /// UI-level parameter values (pre-encoding, human-readable); used for the
    /// detail sheet and to rebuild the payload on Retry.
    let parameters: [String: JSONValue]
    var refFileNames: [String]      // refs/<id>-ref<N>.jpg copies of the inputs
    var endRefFileName: String?
    let costEstimate: Double
    let createdAt: Date
    var status: ItemStatus
    var requestID: String?          // FAL queue request id (videos)
}
