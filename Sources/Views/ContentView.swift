import SwiftUI

struct ContentView: View {
    @State private var updater = Updater.shared

    var body: some View {
        HSplitView {
            ControlPanelView()
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            GalleryView()
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                switch updater.availability {
                case .localBuild(let version, let build):
                    Button {
                        updater.applyLocalUpdate()
                    } label: {
                        Label(tr("Update", "更新"), systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .help(tr("Install new build \(version) (\(build)) and relaunch",
                             "安裝新版本 \(version)（\(build)）並重新啟動"))
                case .remoteRelease(let tag, _):
                    Button {
                        updater.openRemoteUpdate()
                    } label: {
                        Label(tr("Update \(tag)", "更新 \(tag)"),
                              systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .help(tr("Download the new release", "下載新版本"))
                default:
                    EmptyView()
                }
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(tr("Settings (⌘,)", "設定（⌘,）"))
            }
        }
        .task {
            updater.checkOnLaunch()
        }
    }
}
