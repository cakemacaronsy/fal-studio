import SwiftUI

/// The gallery wall (作品牆): this session's works up top, older works
/// grouped in a collapsible "Past generations" section.
struct GalleryView: View {
    enum MediaFilter: String, CaseIterable {
        case all, images, videos

        var title: String {
            switch self {
            case .all: return tr("All", "全部")
            case .images: return tr("Images", "圖片")
            case .videos: return tr("Videos", "影片")
            }
        }

        func matches(_ item: GalleryItem) -> Bool {
            switch self {
            case .all: return true
            case .images: return item.kind == .image
            case .videos: return item.kind == .video
            }
        }
    }

    @Environment(LibraryStore.self) private var library
    @State private var selectedItem: GalleryItem?
    @State private var showPast = false
    @State private var appliedInitialExpand = false
    @State private var mediaFilter: MediaFilter = .all

    private var currentItems: [GalleryItem] {
        library.sortedItems.filter { $0.createdAt >= library.launchedAt && mediaFilter.matches($0) }
    }

    private var pastItems: [GalleryItem] {
        library.sortedItems.filter { $0.createdAt < library.launchedAt && mediaFilter.matches($0) }
    }

    var body: some View {
        Group {
            if library.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        filterTabs

                        if currentItems.isEmpty && pastItems.isEmpty {
                            Text(tr("No \(mediaFilter.title.lowercased()) yet.",
                                    "還沒有\(mediaFilter.title)作品。"))
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }

                        if !currentItems.isEmpty {
                            sectionHeader(tr("This session", "本次生成"),
                                          count: currentItems.count)
                            grid(for: currentItems)
                        }
                        if !pastItems.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showPast.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showPast ? "chevron.down" : "chevron.right")
                                        .font(.caption.weight(.semibold))
                                    Text(tr("Past generations", "過往作品"))
                                        .font(.caption.weight(.semibold))
                                    Text("\(pastItems.count)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
                                }
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, currentItems.isEmpty ? 0 : 8)

                            if showPast {
                                grid(for: pastItems.reversed())  // newest past work first
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .sheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item)
        }
        .onAppear {
            // Nothing new yet on launch → open the past section so the wall
            // isn't a lone collapsed row.
            if !appliedInitialExpand {
                appliedInitialExpand = true
                showPast = currentItems.isEmpty
            }
        }
    }

    /// Media-type tabs (all / images / videos), the way Higgsfield's asset
    /// library segments its gallery.
    private var filterTabs: some View {
        HStack(spacing: 4) {
            ForEach(MediaFilter.allCases, id: \.self) { filter in
                let selected = mediaFilter == filter
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        mediaFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selected
                                                   ? Color.accentColor.opacity(0.18)
                                                   : Color(nsColor: .quaternarySystemFill)))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
        }
        .foregroundStyle(.secondary)
    }

    private func grid(for items: [GalleryItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
                  spacing: 16) {
            ForEach(items) { item in
                GalleryCardView(item: item) {
                    if item.status == .completed {
                        selectedItem = item
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(tr("Your gallery wall is empty", "作品牆還是空的"))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(tr("Describe something on the left and press Generate.",
                    "在左邊描述想生成的內容，然後按「生成」。"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}
