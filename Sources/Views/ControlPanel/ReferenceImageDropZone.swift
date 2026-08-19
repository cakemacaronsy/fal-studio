import SwiftUI
import UniformTypeIdentifiers

/// Unified, always-optional reference-image zone. The user just adds images;
/// the model family resolves the endpoint automatically (none → text-to-x,
/// one → image-to-video, several → edit/reference) and the caption shows the
/// resolved mode. An end-frame slot appears when the family supports it.
struct ReferenceImageDropZone: View {
    @Bindable var draft: GenerationDraft
    @State private var isTargeted = false
    @State private var isEndTargeted = false
    @State private var showImporter = false
    @State private var importTargetIsEnd = false
    @State private var markingRef: RefImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("Reference images (optional)", "參考圖（選填）")
                     + " \(draft.refImages.count)/\(draft.maxRefImages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let caption = draft.variantCaption {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }

            thumbnailStrip

            if draft.refImages.count < draft.maxRefImages {
                dropTarget
            }

            if draft.supportsEndFrame && !draft.refImages.isEmpty {
                endFrameRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(item: $markingRef) { ref in
            AnnotationEditor(image: ref.preview) { data in
                draft.applyAnnotation(data, toRef: ref.id)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: !importTargetIsEnd && draft.maxRefImages > 1) { result in
            guard let urls = try? result.get() else { return }
            if importTargetIsEnd {
                if let url = urls.first { draft.setEndImage(url: url) }
            } else {
                draft.addRefImages(urls: urls)
            }
        }
    }

    // MARK: Thumbnails

    @ViewBuilder
    private var thumbnailStrip: some View {
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
                            markButton(for: ref)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .bottomTrailing)
                        }
                    }
                }
                .padding(2)
            }
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .quaternarySystemFill))
            .dashedDropBorder(targeted: isTargeted)
            .frame(height: draft.refImages.isEmpty ? 76 : 44)
            .overlay {
                Label(draft.refImages.isEmpty
                      ? tr("Drop images here — or none for pure text mode", "拖放圖片到這裡（不放則為純文字生成）")
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

    // MARK: End frame

    private var endFrameRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
                    .dashedDropBorder(targeted: isEndTargeted)
                    .frame(width: 64, height: 44)
                    .overlay {
                        if let end = draft.endImage {
                            Image(nsImage: end.preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onTapGesture { importTargetIsEnd = true; showImporter = true }
                if draft.endImage != nil {
                    removeButton { draft.endImage = nil }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, isImageFile(url) else { return false }
                draft.setEndImage(url: url)
                return true
            } isTargeted: { isEndTargeted = $0 }

            Text(tr("End frame (optional)", "結尾畫格（選填）"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Helpers

    /// Gemini-style "Mark up": opens the annotation editor for this image.
    private func markButton(for ref: RefImage) -> some View {
        Button {
            markingRef = ref
        } label: {
            Image(systemName: ref.annotated ? "pencil.circle.fill" : "pencil.tip.crop.circle")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, ref.annotated ? Color.red : .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(3)
        .help(tr("Mark up: draw arrows, circles or text to guide the edit",
                 "標記：畫箭頭、圈選或文字來指示修改位置"))
    }

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
