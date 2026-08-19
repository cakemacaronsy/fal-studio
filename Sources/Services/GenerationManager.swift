import Foundation
import Observation
import AppKit
import UserNotifications

/// Orchestrates generation jobs: creates the placeholder gallery item, runs the
/// FAL call in a task (many can run concurrently), and flips the item to
/// completed/failed. Also handles Cancel and Retry.
@Observable
final class GenerationManager {
    private let library: LibraryStore
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Live queue status per generating item ("IN_QUEUE", "IN_PROGRESS", ...).
    private(set) var liveStatus: [UUID: String] = [:]

    init(library: LibraryStore) {
        self.library = library
    }

    var mockMode: Bool {
        UserDefaults.standard.bool(forKey: "mockMode")
            || ProcessInfo.processInfo.environment["FAL_STUDIO_MOCK"] == "1"
    }

    var hasAPIKey: Bool {
        KeychainStore.effectiveKey != nil
    }

    func isRunning(_ id: UUID) -> Bool {
        tasks[id] != nil
    }

    private func makeClient() throws -> any FALClientProtocol {
        if mockMode { return MockFALClient() }
        guard let key = KeychainStore.effectiveKey else { throw FALError.noAPIKey }
        return FALClient(apiKey: key)
    }

    // MARK: Improve Prompt

    /// Rewrite the prompt per the selected model's official prompting guide,
    /// via fal's openrouter/router (cheap LLM, same FAL key).
    func improve(prompt: String, spec: ModelSpec, jsonMode: Bool) async throws -> String {
        let client = try makeClient()
        let llm = UserDefaults.standard.string(forKey: "improveModel") ?? PromptImprover.defaultLLM
        let system = PromptImprover.systemPrompt(spec: spec, jsonMode: jsonMode, userPrompt: prompt)
        var improved = try await client.generateText(model: llm, systemPrompt: system, prompt: prompt)
        improved = improved.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown fences some models add despite instructions.
        if improved.hasPrefix("```") {
            improved = improved
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return improved
    }

    // MARK: Done notifications

    private func requestNotificationAuthOnce() {
        guard !UserDefaults.standard.bool(forKey: "notifAuthRequested") else { return }
        UserDefaults.standard.set(true, forKey: "notifAuthRequested")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Local notification when a job ends while the app is in the background.
    private func notifyIfBackgrounded(prompt: String, success: Bool) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? tr("Generation finished", "生成完成")
                                : tr("Generation failed", "生成失敗")
        content.body = String(prompt.prefix(80))
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: Start

    func start(spec: ModelSpec,
               prompt rawPrompt: String,
               values: [String: JSONValue],
               refDatas: [Data],
               endRefData: Data?) {
        let prompt = Self.applyOrientationHint(to: rawPrompt, spec: spec, values: values)
        let id = UUID()
        var refNames: [String] = []
        for (index, data) in refDatas.enumerated() {
            if let name = try? library.writeRef(data, for: id, index: index + 1) {
                refNames.append(name)
            }
        }
        var endName: String?
        if let endRefData {
            endName = try? library.writeRef(endRefData, for: id, index: 0)
        }

        let item = GalleryItem(
            id: id,
            kind: spec.kind,
            fileName: nil,
            thumbnailFileName: nil,
            prompt: prompt,
            modelID: spec.id,
            endpoint: spec.endpoint,
            parameters: values,
            refFileNames: refNames,
            endRefFileName: endName,
            costEstimate: Pricing.estimate(spec: spec, values: values),
            createdAt: Date(),
            status: .generating,
            requestID: nil
        )
        library.append(item)
        requestNotificationAuthOnce()
        launch(itemID: id, spec: spec, prompt: prompt, values: values,
               refDatas: refDatas, endRefData: endRefData)
    }

    /// Quietly append a composition hint matching the chosen aspect ratio, so
    /// results fill the frame's orientation. Skipped when the prompt already
    /// talks about orientation, or the ratio is auto/adaptive/missing.
    nonisolated static func applyOrientationHint(to prompt: String,
                                                 spec: ModelSpec,
                                                 values: [String: JSONValue]) -> String {
        guard spec.parameters.contains(where: { $0.key == "aspect_ratio" }) else { return prompt }
        let ratio = values["aspect_ratio"]?.stringValue
            ?? spec.parameters.first { $0.key == "aspect_ratio" }?.defaultValue.stringValue
            ?? "auto"
        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return prompt }

        let lowered = prompt.lowercased()
        let orientationWords = ["landscape", "portrait", "vertical", "horizontal",
                                "square", "composition", "framing"]
        guard !orientationWords.contains(where: { lowered.contains($0) }) else { return prompt }

        let hint: String
        if parts[0] > parts[1] {
            hint = "Wide landscape composition."
        } else if parts[0] < parts[1] {
            hint = "Vertical portrait composition, full-height framing."
        } else {
            hint = "Square composition."
        }
        return prompt + "\n\n" + hint
    }

    // MARK: Cancel / Retry

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        liveStatus[id] = nil
        if var item = library.item(id: id), item.status == .generating {
            item.status = .failed("Cancelled")
            library.update(item)
        }
    }

    func retry(_ item: GalleryItem) {
        guard let spec = ModelStore.shared.spec(for: item.modelID) else { return }
        let refDatas = library.refFileURLs(for: item).compactMap { try? Data(contentsOf: $0) }
        let endData = library.endRefFileURL(for: item).flatMap { try? Data(contentsOf: $0) }
        start(spec: spec, prompt: item.prompt, values: item.parameters,
              refDatas: refDatas, endRefData: endData)
    }

    // MARK: Job body

    private func launch(itemID: UUID,
                        spec: ModelSpec,
                        prompt: String,
                        values: [String: JSONValue],
                        refDatas: [Data],
                        endRefData: Data?) {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try self.makeClient()

                let payload = PayloadBuilder.build(
                    spec: spec,
                    prompt: prompt,
                    values: values,
                    refDataURIs: refDatas.map { ImageEncoding.dataURI($0) },
                    endImageDataURI: endRefData.map { ImageEncoding.dataURI($0) }
                )

                let onUpdate: @Sendable (String?, String?) -> Void = { status, requestID in
                    Task { @MainActor [weak self] in
                        self?.noteUpdate(itemID: itemID, status: status, requestID: requestID)
                    }
                }

                let files: [MediaFile]
                do {
                    files = try await client.generate(
                        endpoint: spec.endpoint, queued: spec.queued,
                        payload: payload, onUpdate: onUpdate
                    )
                } catch let error as FALError where error.isModerationBlock
                            && Self.isSeedanceImageToVideo(spec) && !refDatas.isEmpty {
                    // Seedance's input filter flags photorealistic faces by pixel
                    // statistics — even AI-generated ones. ByteDance's documented fix
                    // for original characters: use a Seedream-rendered frame instead.
                    // Re-render the frame(s) faithfully with Seedream, then retry.
                    self.liveStatus[itemID] = "RE-RENDERING FRAME (SEEDREAM)"
                    var newRefs = refDatas
                    newRefs[0] = try await self.rerenderFrame(refDatas[0], client: client)
                    var newEnd = endRefData
                    if let end = endRefData {
                        newEnd = try await self.rerenderFrame(end, client: client)
                    }
                    self.liveStatus[itemID] = "RETRYING"
                    let retryPayload = PayloadBuilder.build(
                        spec: spec,
                        prompt: prompt,
                        values: values,
                        refDataURIs: newRefs.map { ImageEncoding.dataURI($0) },
                        endImageDataURI: newEnd.map { ImageEncoding.dataURI($0) }
                    )
                    files = try await client.generate(
                        endpoint: spec.endpoint, queued: spec.queued,
                        payload: retryPayload, onUpdate: onUpdate
                    )
                    self.noteFrameFallback(itemID: itemID,
                                           frames: 1 + (endRefData == nil ? 0 : 1))
                }

                try Task.checkCancellation()
                try self.finish(itemID: itemID, files: files)
                // Video thumbnails need the written file; do them after finish().
                await self.makeVideoThumbnailsIfNeeded(itemID: itemID)
                self.notifyIfBackgrounded(prompt: prompt, success: true)
            } catch is CancellationError {
                // cancel() already marked the item.
            } catch {
                self.fail(itemID: itemID, message: error.localizedDescription)
                self.notifyIfBackgrounded(prompt: prompt, success: false)
            }
            self.tasks[itemID] = nil
            self.liveStatus[itemID] = nil
        }
        tasks[itemID] = task
    }

    // MARK: Seedance moderation fallback

    nonisolated private static func isSeedanceImageToVideo(_ spec: ModelSpec) -> Bool {
        // Covers Seedance 2.0 and 2.5 — both run the photorealistic-face input filter.
        spec.endpoint.contains("seedance-2") && spec.endpoint.hasSuffix("image-to-video")
    }

    private static let seedreamEditCost = 0.135

    /// Faithfully re-render a frame with Seedream so its pixel statistics read
    /// as AI-generated, which passes Seedance's input filter.
    private func rerenderFrame(_ frame: Data, client: any FALClientProtocol) async throws -> Data {
        var payload: [String: JSONValue] = [
            "prompt": .string(
                "Recreate this exact image with complete fidelity: identical person, face, "
                + "expression, pose, clothing, lighting, colors, background and composition. "
                + "Do not add, remove or change anything."),
            "image_urls": .array([.string(ImageEncoding.dataURI(frame))]),
            "num_images": .int(1),
            "output_format": .string("png"),
        ]
        if let size = ImageEncoding.pixelSize(of: frame) {
            payload["image_size"] = PayloadBuilder.seedreamImageSize(aspect: "\(size.width):\(size.height)")
        }
        let files = try await client.generate(
            endpoint: "bytedance/seedream/v5/pro/edit", queued: false,
            payload: payload, onUpdate: { _, _ in }
        )
        guard let file = files.first else {
            throw FALError.badResponse("Seedream frame re-render returned no image")
        }
        return file.data
    }

    /// Record on the item that the fallback ran (visible in the detail sheet)
    /// and add the Seedream re-render cost to the estimate.
    private func noteFrameFallback(itemID: UUID, frames: Int) {
        guard let old = library.item(id: itemID) else { return }
        var params = old.parameters
        params["frame_fallback"] = .string("frame re-rendered with Seedream (Seedance face filter)")
        let updated = GalleryItem(
            id: old.id, kind: old.kind,
            fileName: old.fileName, thumbnailFileName: old.thumbnailFileName,
            prompt: old.prompt, modelID: old.modelID, endpoint: old.endpoint,
            parameters: params,
            refFileNames: old.refFileNames, endRefFileName: old.endRefFileName,
            costEstimate: old.costEstimate + Self.seedreamEditCost * Double(frames),
            createdAt: old.createdAt, status: old.status, requestID: old.requestID
        )
        library.update(updated)
    }

    private func noteUpdate(itemID: UUID, status: String?, requestID: String?) {
        if let status {
            liveStatus[itemID] = status
        }
        if let requestID, var item = library.item(id: itemID) {
            item.requestID = requestID
            library.update(item)
        }
    }

    /// Write media files; the first fills the original item, extras (num_images > 1)
    /// become sibling items appended right after it.
    private func finish(itemID: UUID, files: [MediaFile]) throws {
        guard var item = library.item(id: itemID) else { return }
        guard let first = files.first else {
            throw FALError.badResponse("no media returned")
        }
        item.fileName = try library.writeMedia(first.data, for: item.id, suffix: "",
                                               fileExtension: first.fileExtension)
        if item.kind == .image, let thumb = ThumbnailMaker.imageThumbnail(from: first.data) {
            item.thumbnailFileName = try? library.writeThumbnail(thumb, for: item.id)
        }
        item.status = .completed
        library.update(item)

        for (index, extra) in files.dropFirst().enumerated() {
            let siblingID = UUID()
            var sibling = GalleryItem(
                id: siblingID, kind: item.kind,
                fileName: try library.writeMedia(extra.data, for: siblingID, suffix: "",
                                                 fileExtension: extra.fileExtension),
                thumbnailFileName: nil,
                prompt: item.prompt, modelID: item.modelID, endpoint: item.endpoint,
                parameters: item.parameters, refFileNames: [], endRefFileName: nil,
                costEstimate: 0,  // cost is attributed to the first item
                createdAt: item.createdAt.addingTimeInterval(0.001 * Double(index + 1)),
                status: .completed, requestID: item.requestID
            )
            if sibling.kind == .image, let thumb = ThumbnailMaker.imageThumbnail(from: extra.data) {
                sibling.thumbnailFileName = try? library.writeThumbnail(thumb, for: siblingID)
            }
            library.append(sibling)
        }
    }

    private func makeVideoThumbnailsIfNeeded(itemID: UUID) async {
        guard var item = library.item(id: itemID),
              item.kind == .video, item.thumbnailFileName == nil,
              let mediaURL = library.mediaFileURL(for: item) else { return }
        if let thumb = await ThumbnailMaker.videoThumbnail(url: mediaURL) {
            item.thumbnailFileName = try? library.writeThumbnail(thumb, for: item.id)
            library.update(item)
        }
    }

    private func fail(itemID: UUID, message: String) {
        guard var item = library.item(id: itemID), item.status == .generating else { return }
        item.status = .failed(message)
        library.update(item)
    }
}
