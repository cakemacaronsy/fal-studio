import SwiftUI
import AVKit

/// Enlarged preview of a finished work with the prompt and every setting used.
struct ItemDetailSheet: View {
    let item: GalleryItem

    @Environment(LibraryStore.self) private var library
    @Environment(GenerationDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var savedToDownloads = false

    var body: some View {
        HStack(spacing: 0) {
            mediaPane
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.85))

            Divider()

            metadataPane
                .frame(width: 280)
        }
        .frame(minWidth: 780, idealWidth: 900, minHeight: 520, idealHeight: 600)
        .onDisappear { player?.pause() }
    }

    // MARK: Media

    @ViewBuilder
    private var mediaPane: some View {
        if let url = library.mediaFileURL(for: item) {
            if item.kind == .video {
                ZStack {
                    if let player {
                        PlayerView(player: player)
                    } else {
                        ProgressView()
                    }
                }
                .task(id: item.id) {
                    if player == nil {
                        player = AVPlayer(url: url)
                    }
                }
            } else if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                missingMedia
            }
        } else {
            missingMedia
        }
    }

    private var missingMedia: some View {
        Text(tr("Media file missing", "找不到媒體檔案"))
            .foregroundStyle(.secondary)
    }

    // MARK: Metadata

    private var metadataPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(item.kind == .video ? tr("Video", "影片") : tr("Image", "圖片"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(tr("Prompt", "提示詞")) {
                        Text(item.prompt)
                            .font(.callout)
                            .textSelection(.enabled)
                    }

                    section(tr("Model", "模型")) {
                        Text(ModelStore.shared.spec(for: item.modelID)?.displayName ?? item.modelID)
                            .font(.callout)
                        Text(item.endpoint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }

                    section(tr("Settings", "設定")) {
                        ForEach(sortedParameters, id: \.0) { key, value in
                            HStack(alignment: .firstTextBaseline) {
                                Text(label(for: key))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(value.displayString)
                                    .font(.caption.weight(.medium))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        if !item.refFileNames.isEmpty || item.endRefFileName != nil {
                            HStack {
                                Text(tr("Reference images", "參考圖"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(item.refFileNames.count + (item.endRefFileName == nil ? 0 : 1))")
                                    .font(.caption.weight(.medium))
                            }
                        }
                    }

                    section(tr("Generation", "生成資訊")) {
                        row(tr("Estimated cost", "預估費用"), String(format: "~$%.2f", item.costEstimate))
                        row(tr("Created", "建立時間"), item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let requestID = item.requestID {
                            row(tr("Request", "請求編號"), String(requestID.prefix(18)))
                        }
                    }
                }
                .padding(14)
            }

            Divider()

            VStack(spacing: 8) {
                if item.kind == .image, let url = library.mediaFileURL(for: item) {
                    Button {
                        draft.makeVideo(from: url)
                        dismiss()
                    } label: {
                        Label(tr("Make video from this image", "一鍵轉成影片"),
                              systemImage: "video.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    draft.load(item: item,
                               refURLs: library.refFileURLs(for: item),
                               endURL: library.endRefFileURL(for: item))
                    dismiss()
                } label: {
                    Label(tr("Reuse prompt & settings", "重用提示詞與設定"),
                          systemImage: "arrow.counterclockwise.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    if (try? library.downloadToDownloads(item)) != nil {
                        savedToDownloads = true
                    }
                } label: {
                    Label(savedToDownloads ? tr("Saved to Downloads", "已儲存到「下載」")
                                           : tr("Download", "下載"),
                          systemImage: savedToDownloads ? "checkmark.circle" : "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(14)
        }
    }

    private var sortedParameters: [(String, JSONValue)] {
        item.parameters.sorted { $0.key < $1.key }
    }

    private func label(for key: String) -> String {
        if let spec = ModelStore.shared.spec(for: item.modelID),
           let param = spec.parameters.first(where: { $0.key == key }) {
            return param.label
        }
        return key.replacingOccurrences(of: "_", with: " ")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}
