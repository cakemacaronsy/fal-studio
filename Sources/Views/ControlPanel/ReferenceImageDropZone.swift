import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop area for reference images. Two labeled slots for
/// image-to-video models (start / optional end frame), a thumbnail strip
/// with a drop target for multi-reference models.
struct ReferenceImageDropZone: View {
    @Bindable var draft: GenerationDraft
    @State private var isTargeted = false
    @State private var isEndTargeted = false
    @State private var showImporter = false
    @State private var importTargetIsEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch draft.spec.refImages {
            case .startEnd:
                HStack(spacing: 10) {
                    frameSlot(image: draft.refImages.first,
                              label: tr("Start frame", "起始畫格"),
                              targeted: $isTargeted,
                              onDrop: { draft.refImages = []; draft.addRefImages(urls: [$0]) },
                              onClear: { draft.refImages = [] },
                              onBrowse: { importTargetIsEnd = false; showImporter = true })
                    frameSlot(image: draft.endImage,
                              label: tr("End frame (optional)", "結尾畫格（選填）"),
                              targeted: $isEndTargeted,
                              onDrop: { draft.setEndImage(url: $0) },
                              onClear: { draft.endImage = nil },
                              onBrowse: { importTargetIsEnd = true; showImporter = true })
                }
            case .multiple(let max):
                multiZone(max: max)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: !importTargetIsEnd && draft.maxRefImages > 1) { result in
            guard let urls = try? result.get() else { return }
            if importTargetIsEnd {
                if let url = urls.first { draft.setEndImage(url: url) }
            } else {
                if case .startEnd = draft.spec.refImages { draft.refImages = [] }
                draft.addRefImages(urls: urls)
            }
        }
    }

    private var title: String {
        switch draft.spec.refImages {
        case .multiple(let max):
            return tr("Reference images", "參考圖") + " (\(draft.refImages.count)/\(max))"
        default:
            return tr("Frames", "畫格")
        }
    }

    // MARK: Start/end slots

    private func frameSlot(image: RefImage?,
                           label: String,
                           targeted: Binding<Bool>,
                           onDrop: @escaping (URL) -> Void,
                           onClear: @escaping () -> Void,
                           onBrowse: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
                    .dashedDropBorder(targeted: targeted.wrappedValue)
                    .frame(height: 76)
                    .overlay {
                        if let image {
                            Image(nsImage: image.preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onTapGesture(perform: onBrowse)
                if image != nil {
                    removeButton(action: onClear)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, isImageFile(url) else { return false }
                onDrop(url)
                return true
            } isTargeted: { targeted.wrappedValue = $0 }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Multi-image zone

    private func multiZone(max: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !draft.refImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.refImages) { ref in
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: ref.preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                removeButton {
                                    draft.refImages.removeAll { $0.id == ref.id }
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
            if draft.refImages.count < max {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
                    .dashedDropBorder(targeted: isTargeted)
                    .frame(height: draft.refImages.isEmpty ? 76 : 44)
                    .overlay {
                        Label(draft.refImages.isEmpty ? tr("Drop images here", "拖放圖片到這裡")
                                                      : tr("Drop more", "可再拖入"),
                              systemImage: "photo.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .onTapGesture { importTargetIsEnd = false; showImporter = true }
                    .dropDestination(for: URL.self) { urls, _ in
                        let images = urls.filter(isImageFile)
                        guard !images.isEmpty else { return false }
                        draft.addRefImages(urls: images)
                        return true
                    } isTargeted: { isTargeted = $0 }
            }
        }
    }

    // MARK: Helpers

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(3)
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

private extension View {
    /// Dashed border that highlights while a drag hovers over the zone.
    func dashedDropBorder(targeted: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [5, 4]))
        )
    }
}
