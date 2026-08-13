import SwiftUI

/// One card on the gallery wall: thumbnail with hover Download/Delete for
/// finished works, a spinner card while generating, error card on failure.
struct GalleryCardView: View {
    let item: GalleryItem
    let onSelect: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(GenerationManager.self) private var generator
    @Environment(GenerationDraft.self) private var draft
    @State private var isHovering = false
    @State private var confirmDelete = false
    @State private var thumbnail: NSImage?

    private let cardHeight: CGFloat = 168

    var body: some View {
        content
            .frame(height: cardHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .confirmationDialog(tr("Delete this work?", "刪除這件作品？"), isPresented: $confirmDelete) {
                Button(tr("Delete", "刪除"), role: .destructive) {
                    library.delete(item)
                }
            } message: {
                Text(tr("The file is removed from your gallery. This can't be undone.",
                        "檔案將從作品牆移除，無法復原。"))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.status {
        case .generating:
            generatingCard
        case .failed(let message):
            failedCard(message)
        case .completed:
            completedCard
        }
    }

    // MARK: Completed

    private var completedCard: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .quaternarySystemFill))
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            if item.kind == .video {
                videoBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomLeading)
            }

            if isHovering {
                HStack(spacing: 6) {
                    if item.kind == .image, let url = library.mediaFileURL(for: item) {
                        overlayButton("photo.badge.arrow.down.fill",
                                      help: tr("Use as reference / start frame", "作為參考圖／起始畫格")) {
                            draft.useAsReference(fileURL: url)
                        }
                    }
                    overlayButton("arrow.down.circle.fill",
                                  help: tr("Save to Downloads", "儲存到「下載」")) {
                        _ = try? library.downloadToDownloads(item)
                    }
                    overlayButton("trash.circle.fill", help: tr("Delete", "刪除")) {
                        confirmDelete = true
                    }
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .task(id: item.thumbnailFileName ?? item.fileName) {
            loadThumbnail()
        }
    }

    private var videoBadge: some View {
        Image(systemName: "play.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.5), in: Circle())
            .padding(8)
            .allowsHitTesting(false)
    }

    private func overlayButton(_ symbol: String, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func loadThumbnail() {
        if let url = library.thumbnailFileURL(for: item), let image = NSImage(contentsOf: url) {
            thumbnail = image
        } else if item.kind == .image,
                  let url = library.mediaFileURL(for: item),
                  let image = NSImage(contentsOf: url) {
            thumbnail = image
        }
    }

    // MARK: Generating

    private var generatingCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                ProgressView()
                Text(tr("Generating…", "生成中…"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(item.createdAt))
                    Text("\(statusLine) · \(elapsed)s")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isHovering {
                Button {
                    generator.cancel(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .padding(8)
                .transition(.opacity)
            }
        }
    }

    private var statusLine: String {
        switch generator.liveStatus[item.id] {
        case "IN_QUEUE": return "queued"
        case "IN_PROGRESS": return "in progress"
        case "DOWNLOADING": return "downloading"
        case "GENERATING", .none: return "working"
        case .some(let other): return other.lowercased()
        }
    }

    // MARK: Failed

    private func failedCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            HStack(spacing: 10) {
                Button(tr("Retry", "重試")) {
                    generator.retry(item)
                    library.delete(item)
                }
                .controlSize(.small)
                Button(tr("Delete", "刪除"), role: .destructive) {
                    confirmDelete = true
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
