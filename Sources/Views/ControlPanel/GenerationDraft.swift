import SwiftUI
import Observation

/// A reference image the user dropped in, already encoded for upload.
struct RefImage: Identifiable {
    let id = UUID()
    let encoded: ImageEncoding.EncodedImage
    let preview: NSImage
    var annotated = false   // true after Mark up (red edit markings baked in)
}

/// The in-progress state of the control panel.
@Observable
final class GenerationDraft {
    var mode: MediaKind = .image
    /// A family id ("fam-seedance") or a custom model's spec id.
    var modelID: String = ModelCatalog.defaultFamilyID(for: .image)
    var prompt: String = ""
    var paramValues: [String: JSONValue] = [:]
    var refImages: [RefImage] = []
    var endImage: RefImage?

    // Improve Prompt state
    var jsonMode = false
    var isImproving = false
    var promptBackup: String?     // set when Improve replaces the prompt; enables revert
    var improveError: String?

    /// The concrete endpoint spec, resolved from the family + the reference
    /// images currently provided: none → text-to-x, one (or an end frame) →
    /// image-to-video, several → edit/reference variant.
    var spec: ModelSpec {
        if let family = ModelCatalog.family(id: modelID) {
            return ModelCatalog.spec(for: resolvedVariantID(of: family)) ?? ModelCatalog.all[0]
        }
        return ModelStore.shared.spec(for: modelID) ?? ModelCatalog.all[0]
    }

    private func resolvedVariantID(of family: ModelFamily) -> String {
        if refImages.isEmpty && endImage == nil {
            return family.baseSpecID
        }
        if refImages.count >= 2, let multiple = family.multipleSpecID {
            return multiple
        }
        if let startEnd = family.startEndSpecID {
            return startEnd
        }
        return family.multipleSpecID ?? family.baseSpecID
    }

    /// Short label showing which endpoint the current inputs resolve to.
    var variantCaption: String? {
        guard let family = ModelCatalog.family(id: modelID) else { return nil }
        let variant = resolvedVariantID(of: family)
        if variant == family.baseSpecID {
            return mode == .video ? tr("Mode: text → video", "模式：文生影片")
                                  : tr("Mode: text → image", "模式：文生圖")
        }
        if variant == family.startEndSpecID {
            return tr("Mode: image → video (start frame)", "模式：圖生影片（起始畫格）")
        }
        return mode == .video ? tr("Mode: references → video", "模式：參考圖生影片")
                              : tr("Mode: image edit", "模式：圖片編輯")
    }

    func selectMode(_ newMode: MediaKind) {
        guard newMode != mode else { return }
        mode = newMode
        selectModel(ModelCatalog.defaultFamilyID(for: newMode))
    }

    func selectModel(_ id: String) {
        // Normalize: family id stays; a concrete spec id (old gallery items)
        // maps back to its family; custom ids stay as-is.
        if ModelCatalog.family(id: id) != nil {
            modelID = id
        } else if let familyID = ModelCatalog.familyID(forSpecID: id) {
            modelID = familyID
        } else if ModelStore.shared.spec(for: id) != nil {
            modelID = id
        } else {
            return
        }
        // Trim reference images to the new model's capability.
        refImages = Array(refImages.prefix(max(maxRefImages, 0)))
        if !supportsEndFrame {
            endImage = nil
        }
        // Keep values whose parameter still exists with the same kind of options;
        // reset the rest to the new model's defaults.
        let newSpec = spec
        var migrated: [String: JSONValue] = [:]
        for param in newSpec.parameters {
            if let old = paramValues[param.key], isValid(old, for: param) {
                migrated[param.key] = old
            } else {
                migrated[param.key] = param.defaultValue
            }
        }
        paramValues = migrated
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

    /// Capacity across the family's variants (so the drop zone can offer
    /// every possibility and the variant resolves from what's provided).
    var maxRefImages: Int {
        if let family = ModelCatalog.family(id: modelID) {
            var capacity = family.startEndSpecID != nil ? 1 : 0
            if let multipleID = family.multipleSpecID,
               let multipleSpec = ModelCatalog.spec(for: multipleID),
               case .multiple(let max) = multipleSpec.refImages {
                capacity = Swift.max(capacity, max)
            }
            return capacity
        }
        switch spec.refImages {
        case .none: return 0
        case .startEnd: return 1
        case .multiple(let max): return max
        }
    }

    /// End frame is only meaningful while the inputs resolve to the
    /// image-to-video variant (zero or one start image).
    var supportsEndFrame: Bool {
        if let family = ModelCatalog.family(id: modelID) {
            guard let startEndID = family.startEndSpecID, refImages.count <= 1 else { return false }
            return ModelCatalog.spec(for: startEndID)?.endImagePayloadKey != nil
        }
        if case .startEnd = spec.refImages {
            return spec.endImagePayloadKey != nil
        }
        return false
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

    // MARK: Mark up (Gemini-style annotation)

    var hasAnnotatedRefs: Bool {
        refImages.contains(where: \.annotated) || endImage?.annotated == true
    }

    /// Replace a reference image with its annotated version.
    func applyAnnotation(_ data: Data, toRef id: UUID) {
        guard let preview = NSImage(data: data) else { return }
        let encoded = ImageEncoding.EncodedImage(data: data, mime: ImageEncoding.mime(forData: data))
        if let index = refImages.firstIndex(where: { $0.id == id }) {
            refImages[index] = RefImage(encoded: encoded, preview: preview, annotated: true)
        } else if endImage?.id == id {
            endImage = RefImage(encoded: encoded, preview: preview, annotated: true)
        }
    }

    // MARK: Gallery interactions

    /// One-click image→video (OpenArt-style): jump to Seedance with this
    /// image as the start frame — the family resolves to image-to-video.
    func makeVideo(from fileURL: URL) {
        mode = .video
        refImages = []
        endImage = nil
        selectModel(ModelCatalog.defaultFamilyID(for: .video))
        addRefImages(urls: [fileURL])
    }

    /// Load a finished work's image as a reference. If the current model
    /// takes no images at all, switch to the default video family (i2v).
    func useAsReference(fileURL: URL) {
        if maxRefImages == 0 {
            mode = .video
            selectModel(ModelCatalog.defaultFamilyID(for: .video))
        }
        if maxRefImages == 1 {
            refImages = []
        }
        addRefImages(urls: [fileURL])
    }

    /// Restore a gallery item's prompt, model, and settings into the panel.
    func load(item: GalleryItem, refURLs: [URL], endURL: URL?) {
        mode = item.kind
        refImages = []
        endImage = nil
        if ModelCatalog.familyID(forSpecID: item.modelID) != nil
            || ModelStore.shared.spec(for: item.modelID) != nil {
            selectModel(item.modelID)
        } else {
            selectModel(ModelCatalog.defaultFamilyID(for: item.kind))
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
