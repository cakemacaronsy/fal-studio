import SwiftUI

@main
struct FALStudioApp: App {
    @State private var library: LibraryStore
    @State private var generator: GenerationManager
    @State private var draft = GenerationDraft()

    init() {
        let lib = LibraryStore()
        _library = State(initialValue: lib)
        _generator = State(initialValue: GenerationManager(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(generator)
                .environment(draft)
                .frame(minWidth: 880, minHeight: 560)
        }
        Settings {
            SettingsView()
        }
    }
}
