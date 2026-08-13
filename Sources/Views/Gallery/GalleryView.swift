import SwiftUI

/// The gallery wall (作品牆): finished works in generation order,
/// with placeholder cards for in-flight jobs.
struct GalleryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selectedItem: GalleryItem?

    var body: some View {
        Group {
            if library.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
                              spacing: 16) {
                        ForEach(library.sortedItems) { item in
                            GalleryCardView(item: item) {
                                if item.status == .completed {
                                    selectedItem = item
                                }
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
