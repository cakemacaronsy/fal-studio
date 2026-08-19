import Foundation
import AppKit
import Observation
import UserNotifications

/// Keeps the installed app up to date from two sources:
/// 1. The local dev build folder (default ~/Desktop/FAL Studio/build/…) —
///    one click replaces the installed copy and relaunches.
/// 2. Optionally, GitHub Releases (Settings → repo "owner/name") — for copies
///    of the app running on other people's Macs.
@Observable
final class Updater {
    static let shared = Updater()

    enum Availability: Equatable {
        case unknown
        case upToDate
        case localBuild(version: String, build: String)
        case remoteRelease(tag: String, dmgURL: URL)
    }

    private(set) var availability: Availability = .unknown
    private(set) var isChecking = false
    private(set) var lastError: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var devBuildPath: String {
        if let override = UserDefaults.standard.string(forKey: "devBuildPath") {
            return override
        }
        // build.sh records its output path here, so the updater keeps working
        // even when the project folder moves.
        let recorded = NSHomeDirectory()
            + "/Library/Application Support/FAL Studio/dev_build_path.txt"
        if let path = try? String(contentsOfFile: recorded, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        return NSHomeDirectory() + "/Desktop/FAL Studio/build/Build/Products/Release/FAL Studio.app"
    }

    /// Defaults to the project's public repo so every downloaded copy
    /// auto-discovers new releases; users can point elsewhere (or blank it)
    /// in Settings → Updates.
    var githubRepo: String {
        get { UserDefaults.standard.string(forKey: "updateRepo") ?? "cakemacaronsy/fal-studio" }
        set { UserDefaults.standard.set(newValue, forKey: "updateRepo") }
    }

    private init() {}

    // MARK: Check

    func checkOnLaunch() {
        Task {
            await check()
            if case .localBuild = availability {
                notifyUpdateFound()
            } else if case .remoteRelease = availability {
                notifyUpdateFound()
            }
        }
    }

    func check() async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        if let local = localUpdate() {
            availability = local
            return
        }
        if let remote = await remoteUpdate() {
            availability = remote
            return
        }
        availability = .upToDate
    }

    /// A newer build in the dev folder than the running app (skipped when the
    /// running app IS the dev build).
    private func localUpdate() -> Availability? {
        let devURL = URL(fileURLWithPath: devBuildPath)
        guard FileManager.default.fileExists(atPath: devURL.path),
              Bundle.main.bundleURL.standardizedFileURL != devURL.standardizedFileURL,
              let devBundle = Bundle(url: devURL),
              let devBuild = devBundle.infoDictionary?["CFBundleVersion"] as? String,
              let devVersion = devBundle.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        guard numeric(devBuild) > numeric(currentBuild) else { return nil }
        return .localBuild(version: devVersion, build: devBuild)
    }

    /// Latest GitHub release with a .dmg asset, when a repo is configured.
    private func remoteUpdate() async -> Availability? {
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        guard !repo.isEmpty, repo.contains("/"),
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            lastError = tr("Could not reach GitHub releases for \(repo).",
                           "無法讀取 \(repo) 的 GitHub Releases。")
            return nil
        }
        let tag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isNewer(tag, than: currentVersion),
              let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmgURL = URL(string: dmg.browserDownloadURL) else { return nil }
        return .remoteRelease(tag: release.tagName, dmgURL: dmgURL)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    // MARK: Apply

    /// Replace the running app with the dev build and relaunch.
    func applyLocalUpdate() {
        let installed = Bundle.main.bundlePath
        let dev = devBuildPath
        let script = """
        sleep 0.7
        rm -rf "\(installed)"
        cp -R "\(dev)" "\(installed)"
        xattr -dr com.apple.quarantine "\(installed)" 2>/dev/null
        open "\(installed)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Remote releases: open the DMG download in the browser.
    func openRemoteUpdate() {
        if case .remoteRelease(_, let dmgURL) = availability {
            NSWorkspace.shared.open(dmgURL)
        }
    }

    // MARK: Helpers

    private func numeric(_ build: String) -> Double {
        Double(build.replacingOccurrences(of: ".", with: "")) ?? 0
    }

    /// Lightweight semver-ish compare: 1.2 > 1.1.9 style, component by component.
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func notifyUpdateFound() {
        let content = UNMutableNotificationContent()
        content.title = tr("FAL Studio update available", "FAL Studio 有可用更新")
        content.body = tr("Open FAL Studio and click the update button in the toolbar.",
                          "打開 FAL Studio，點工具列的更新按鈕。")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "falstudio-update", content: content, trigger: nil))
    }
}
