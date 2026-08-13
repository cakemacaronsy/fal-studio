import SwiftUI
import Observation

/// A reference image the user dropped in, already encoded for upload.
struct RefImage: Identifiable {
    let id = UUID()
    let encoded: ImageEncoding.EncodedImage
    let preview: NSImage
}

/// The in-progress state of the control panel.
@Observable
final class GenerationDraft {
    var mode: MediaKind = .image
    var modelID: String = ModelCatalog.defaultModelID(for: .image)
    var prompt: String = ""
    var paramValues: [String: JSONValue] = [:]
    var refImages: [RefImage] = []
    var endImage: RefImage?

    // Improve Prompt state
    var jsonMode = false
    var isImproving = false
    var promptBackup: String?     // set when Improve replaces the prompt; enables revert
    var improveError: String?

    var spec: ModelSpec {
        ModelStore.shared.spec(for: modelID) ?? ModelCatalog.all[0]
    }

    func selectMode(_ newMode: MediaKind) {
        guard newMode != mode else { return }
        mode = newMode
        selectModel(ModelCatalog.defaultModelID(for: newMode))
    }

    func selectModel(_ id: String) {
        guard let newSpec = ModelStore.shared.spec(for: id) else { return }
        modelID = id
        // Keep values whose parameter still exists with the same kind of options;
        // reset the rest to the new model's defaults.
        var migrated: [String: JSONValue] = [:]
        for param in newSpec.parameters {
            if let old = paramValues[param.key], isValid(old, for: param) {
                migrated[param.key] = old
            } else {
                migrated[param.key] = param.defaultValue
            }
        }
        paramValues = migrated
        // Trim reference images to what the new model accepts.
        switch newSpec.refImages {
        case .none:
            refImages = []
            endImage = nil
        case .startEnd:
            refImages = Array(refImages.prefix(1))
        case .multiple(let max):
            refImages = Array(refImages.prefix(max))
            endImage = nil
        }
    }

    private func isValid(_ value: JSONValue, for param: ParameterSpec) -> Bool {
        switch param.kind {
        case .choice(let options, _):
            return value.stringValue.map { options.contains($0) } ?? false
        case .toggle:
            return value.boolValue != nil
        case .stepper(let range, _):
            return value.intValue.map { range.contains($0) } ?? false
        }
    }

    // MARK: Values

    func value(for param: ParameterSpec) -> JSONValue {
        paramValues[param.key] ?? param.defaultValue
    }

    func setValue(_ value: JSONValue, for key: String) {
        paramValues[key] = value
    }

    var estimatedCost: Double {
        Pricing.estimate(spec: spec, values: paramValues)
    }

    // MARK: Reference images

    var maxRefImages: Int {
        switch spec.refImages {
        case .none: return 0
        case .startEnd: return 1
        case .multiple(let max): return max
        }
    }

    func addRefImages(urls: [URL]) {
        for url in urls {
            guard refImages.count < maxRefImages else { break }
            guard let encoded = try? ImageEncoding.encodeForUpload(fileURL: url),
                  let preview = NSImage(data: encoded.data) else { continue }
            refImages.append(RefImage(encoded: encoded, preview: preview))
        }
    }

    func setEndImage(url: URL) {
        guard let encoded = try? ImageEncoding.encodeForUpload(fileURL: url),
              let preview = NSImage(data: encoded.data) else { return }
        endImage = RefImage(encoded: encoded, preview: preview)
    }

    // MARK: Improve Prompt

    func applyImproved(_ improved: String) {
        promptBackup = prompt
        prompt = improved
    }

    func revertImproved() {
        if let backup = promptBackup {
            prompt = backup
            promptBackup = nil
        }
    }

    // MARK: Gallery interactions

    /// Load a finished work's image as the reference/start frame. If the
    /// current model takes no images, switch to Seedance image-to-video.
    func useAsReference(fileURL: URL) {
        if spec.refImages == .none {
            mode = .video
            selectModel("seedance-i2v")
        }
        if case .startEnd = spec.refImages {
            refImages = []
        }
        addRefImages(urls: [fileURL])
    }

    /// Restore a gallery item's prompt, model, and settings into the panel.
    func load(item: GalleryItem, refURLs: [URL], endURL: URL?) {
        mode = item.kind
        if ModelStore.shared.spec(for: item.modelID) != nil {
            selectModel(item.modelID)
        } else {
            selectModel(ModelCatalog.defaultModelID(for: item.kind))
        }
        prompt = item.prompt
        promptBackup = nil
        for param in spec.parameters {
            if let value = item.parameters[param.key], isValid(value, for: param) {
                paramValues[param.key] = value
            }
        }
        refImages = []
        endImage = nil
        addRefImages(urls: refURLs)
        if let endURL {
            setEndImage(url: endURL)
        }
    }
}
