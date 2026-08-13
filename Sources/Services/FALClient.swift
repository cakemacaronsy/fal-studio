import Foundation

nonisolated struct MediaFile: Sendable {
    let data: Data
    let fileExtension: String  // "png" / "jpeg" / "mp4"
}

nonisolated enum FALError: Error, LocalizedError {
    case noAPIKey
    case http(code: Int, body: String)
    case badResponse(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No FAL API key. Add one in Settings (⌘,)."
        case .http(let code, let body):
            let detail = body.prefix(300)
            return "FAL returned HTTP \(code)\(detail.isEmpty ? "" : ": \(detail)")"
        case .badResponse(let message):
            return "Unexpected FAL response: \(message)"
        case .timeout:
            return "Timed out waiting for the generation to finish."
        }
    }
}

extension FALError {
    /// True when the failure looks like Seedance's input content filter
    /// (photorealistic-face / IP moderation) rather than a technical error.
    var isModerationBlock: Bool {
        guard case .http(_, let body) = self else { return false }
        let text = body.lowercased()
        let markers = ["moderation", "content policy", "content_policy", "not eligible",
                       "flagged", "sensitive", "risk control", "face", "portrait",
                       "violat", "prohibited", "rejected by", "safety"]
        return markers.contains { text.contains($0) }
    }
}

nonisolated protocol FALClientProtocol: Sendable {
    /// Runs one generation and returns the finished media bytes.
    /// - queued: false → sync https://fal.run (images); true → https://queue.fal.run + polling (video)
    /// - onUpdate: live progress ("IN_QUEUE", "IN_PROGRESS", ...) and the queue request id when known.
    func generate(endpoint: String,
                  queued: Bool,
                  payload: [String: JSONValue],
                  onUpdate: @escaping @Sendable (_ status: String?, _ requestID: String?) -> Void)
        async throws -> [MediaFile]

    /// One-shot text generation (used by Improve Prompt) via fal's
    /// openrouter/router endpoint. Returns the model's text output.
    func generateText(model: String, systemPrompt: String, prompt: String) async throws -> String
}

nonisolated struct FALClient: FALClientProtocol {
    let apiKey: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300   // sync image calls can be slow
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    private static let queueTimeout: TimeInterval = 1800
    private static let pollInterval: TimeInterval = 5

    func generate(endpoint: String,
                  queued: Bool,
                  payload: [String: JSONValue],
                  onUpdate: @escaping @Sendable (_ status: String?, _ requestID: String?) -> Void)
        async throws -> [MediaFile] {
        let result: [String: JSONValue]
        if queued {
            result = try await runQueued(endpoint: endpoint, payload: payload, onUpdate: onUpdate)
        } else {
            onUpdate("GENERATING", nil)
            result = try await postJSON(url: "https://fal.run/\(endpoint)", payload: payload)
        }
        onUpdate("DOWNLOADING", nil)
        return try await collectMedia(from: result)
    }

    func generateText(model: String, systemPrompt: String, prompt: String) async throws -> String {
        let payload: [String: JSONValue] = [
            "model": .string(model),
            "system_prompt": .string(systemPrompt),
            "prompt": .string(prompt),
            "temperature": .double(0.7),
            "max_tokens": .int(1200),
        ]
        let result = try await postJSON(url: "https://fal.run/openrouter/router", payload: payload)
        guard let output = result["output"]?.stringValue, !output.isEmpty else {
            throw FALError.badResponse("LLM returned no output")
        }
        return output
    }

    // MARK: Queue flow (video)

    private func runQueued(endpoint: String,
                           payload: [String: JSONValue],
                           onUpdate: @escaping @Sendable (String?, String?) -> Void)
        async throws -> [String: JSONValue] {
        let job = try await postJSON(url: "https://queue.fal.run/\(endpoint)", payload: payload)
        guard let statusURL = job["status_url"]?.stringValue,
              let responseURL = job["response_url"]?.stringValue else {
            throw FALError.badResponse("queue submission had no status_url/response_url")
        }
        onUpdate("IN_QUEUE", job["request_id"]?.stringValue)

        let deadline = Date().addingTimeInterval(Self.queueTimeout)
        while true {
            if Date() > deadline { throw FALError.timeout }
            let status = try await getJSON(url: statusURL)
            let state = status["status"]?.stringValue ?? "UNKNOWN"
            onUpdate(state, nil)
            if state == "COMPLETED" { break }
            try await Task.sleep(for: .seconds(Self.pollInterval))
        }
        return try await getJSON(url: responseURL)
    }

    // MARK: Result parsing

    private func collectMedia(from result: [String: JSONValue]) async throws -> [MediaFile] {
        var entries: [[String: JSONValue]] = []
        if case .some(.array(let images)) = result["images"] {
            entries = images.compactMap { if case .object(let o) = $0 { return o } else { return nil } }
        } else if case .some(.object(let video)) = result["video"] {
            entries = [video]
        } else if case .some(.array(let videos)) = result["videos"] {
            entries = videos.compactMap { if case .object(let o) = $0 { return o } else { return nil } }
        }
        guard !entries.isEmpty else {
            let raw = (try? JSONValue.encodeToData(result)).flatMap { String(data: $0, encoding: .utf8) }
            throw FALError.badResponse("no media in response: \(raw?.prefix(500) ?? "")")
        }
        var files: [MediaFile] = []
        for entry in entries {
            guard let url = entry["url"]?.stringValue else { continue }
            let ext = fileExtension(for: entry, url: url)
            if url.hasPrefix("data:") {
                guard let comma = url.firstIndex(of: ","),
                      let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else {
                    throw FALError.badResponse("undecodable data URI in result")
                }
                files.append(MediaFile(data: data, fileExtension: ext))
            } else {
                files.append(MediaFile(data: try await download(url: url), fileExtension: ext))
            }
        }
        guard !files.isEmpty else { throw FALError.badResponse("media entries had no URLs") }
        return files
    }

    private func fileExtension(for entry: [String: JSONValue], url: String) -> String {
        if let contentType = entry["content_type"]?.stringValue {
            if contentType.contains("mp4") || contentType.contains("video") { return "mp4" }
            if contentType.contains("jpeg") || contentType.contains("jpg") { return "jpeg" }
            if contentType.contains("png") { return "png" }
        }
        if url.hasPrefix("data:image/jpeg") { return "jpeg" }
        let path = URL(string: url)?.pathExtension.lowercased() ?? ""
        if ["png", "jpeg", "jpg", "mp4", "webm", "mov"].contains(path) {
            return path == "jpg" ? "jpeg" : path
        }
        return "png"
    }

    // MARK: HTTP helpers

    private func postJSON(url: String, payload: [String: JSONValue]) async throws -> [String: JSONValue] {
        guard let requestURL = URL(string: url) else { throw FALError.badResponse("bad URL \(url)") }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONValue.encodeToData(payload)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    private func getJSON(url: String) async throws -> [String: JSONValue] {
        guard let requestURL = URL(string: url) else { throw FALError.badResponse("bad URL \(url)") }
        var request = URLRequest(url: requestURL)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> [String: JSONValue] {
        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FALError.http(code: http.statusCode,
                                body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            throw FALError.badResponse(String(data: data, encoding: .utf8)?.prefix(300).description
                                       ?? "undecodable body")
        }
    }

    private func download(url: String) async throws -> Data {
        guard let mediaURL = URL(string: url) else { throw FALError.badResponse("bad media URL") }
        let (data, response) = try await Self.session.data(from: mediaURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FALError.http(code: http.statusCode, body: "downloading result media")
        }
        return data
    }
}
