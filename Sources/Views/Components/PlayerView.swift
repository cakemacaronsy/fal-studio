import SwiftUI
import AVKit

/// AppKit AVPlayerView wrapped for SwiftUI. Replaces SwiftUI's VideoPlayer,
/// whose _AVKit_SwiftUI overlay crashed at metadata-instantiation time when
/// the detail sheet opened (getSuperclassMetadata abort on macOS 26).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}
