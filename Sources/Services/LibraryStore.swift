import Foundation
import Observation

/// Owns the gallery items and persists them (plus media/thumbnail/ref files)
/// under ~/Library/Application Support/FAL Studio/.
@Observable
final class LibraryStore {
    private(set) var items: [GalleryItem] = []

    /// When this app session started — the gallery groups older works
    /// under "Past generations".
    let launchedAt = Date()

    let rootURL: URL
    let mediaURL: URL
    let thumbnailsURL: URL
    let refsURL: URL

    private var saveTask: Task<Void, Never>?
    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        rootURL = appSupport.appendingPathComponent("FAL Studio", isDirectory: true)
        mediaURL = rootURL.appendingPathComponent("media", isDirectory: true)
        thumbnailsURL = rootURL.appendingPathComponent("thumbnails", isDirectory: true)
        refsURL = rootURL.appendingPathComponent("refs", isDirectory: true)
        for url in [rootURL, mediaURL, thumbnailsURL, refsURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: Item access

    /// Gallery order: oldest first (generation order).
    var sortedItems: [GalleryItem] {
        items.sorted { $0.createdAt < $1.createdAt }
    }

    func item(id: UUID) -> GalleryItem? {
        items.first { $0.id == id }
    }

    func append(_ item: GalleryItem) {
        items.append(item)
        scheduleSave()
    }

    func update(_ item: GalleryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        scheduleSave()
    }

    func delete(_ item: GalleryItem) {
        items.removeAll { $0.id == item.id }
        var files: [URL] = []
        if let name = item.fileName { files.append(mediaURL.appendingPathComponent(name)) }
        if let name = item.thumbnailFileName { files.append(thumbnailsURL.appendingPathComponent(name)) }
        files += item.refFileNames.map { refsURL.appendingPathComponent($0) }
        if let end = item.endRefFileName { files.append(refsURL.appendingPathComponent(end)) }
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
        scheduleSave()
    }

    // MARK: File paths

    func mediaFileURL(for item: GalleryItem) -> URL? {
        item.fileName.map { mediaURL.appendingPathComponent($0) }
    }

    func thumbnailFileURL(for item: GalleryItem) -> URL? {
        item.thumbnailFileName.map { thumbnailsURL.appendingPathComponent($0) }
    }

    func refFileURLs(for item: GalleryItem) -> [URL] {
        item.refFileNames.map { refsURL.appendingPathComponent($0) }
    }

    func endRefFileURL(for item: GalleryItem) -> URL? {
        item.endRefFileName.map { refsURL.appendingPathComponent($0) }
    }

    // MARK: Media/ref writing

    func writeMedia(_ data: Data, for id: UUID, suffix: String, fileExtension: String) throws -> String {
        let name = "\(id.uuidString)\(suffix).\(fileExtension)"
        try data.write(to: mediaURL.appendingPathComponent(name), options: .atomic)
        return name
    }

    func writeThumbnail(_ data: Data, for id: UUID) throws -> String {
        let name = "\(id.uuidString).jpg"
        try data.write(to: thumbnailsURL.appendingPathComponent(name), options: .atomic)
        return name
    }

    func writeRef(_ data: Data, for id: UUID, index: Int) throws -> String {
        let ext = ImageEncoding.mime(forData: data) == "image/png" ? "png" : "jpg"
        let name = "\(id.uuidString)-ref\(index).\(ext)"
        try data.write(to: refsURL.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Copy an item's media file to ~/Downloads with a readable, unique name.
    @discardableResult
    func downloadToDownloads(_ item: GalleryItem) throws -> URL {
        guard let source = mediaFileURL(for: item) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let base = "\(item.modelID)-\(formatter.string(from: item.createdAt))"
        let ext = source.pathExtension
        var destination = downloads.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = downloads.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([GalleryItem].self, from: data) else { return }
        // Jobs interrupted by quitting the app can't be resumed (v1); mark them failed.
        for index in loaded.indices where loaded[index].status == .generating {
            loaded[index].status = .failed("Interrupted — the app quit while this was generating.")
        }
        items = loaded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
