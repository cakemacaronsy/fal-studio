import Foundation
import AppKit
import Observation
import UserNotifications

/// Keeps the installed app up to date from two sources:
/// 1. GitHub Releases (Settings → repo "owner/name") — how every normal
///    install updates: it opens the new DMG in the browser.
/// 2. A local dev build, ONLY when this machine actually built the app
///    (build.sh records its output path) AND the running copy sits in a
///    writable /Applications — one click replaces it in place and relaunches.
///    Anything else (running from the DMG, ~/Downloads, or a translocated
///    quarantine path) reports a clear instruction instead of self-destructing.
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

    /// Where this machine's own build lands, if it builds at all. Only a
    /// path recorded by scripts/build.sh (or an explicit override) counts —
    /// there is deliberately NO guessed fallback, so a machine that never
    /// built the app never points at a stale folder.
    var devBuildPath: String? {
        if let override = UserDefaults.standard.string(forKey: "devBuildPath"),
           !override.isEmpty {
            return override
        }
        let recorded = NSHomeDirectory()
            + "/Library/Application Support/FAL Studio/dev_build_path.txt"
        guard let path = try? String(contentsOfFile: recorded, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    /// True when the running bundle is somewhere we may safely replace:
    /// a writable /Applications (system or user), not the DMG, not a
    /// translocated quarantine path.
    var canSelfReplace: Bool {
        let path = Bundle.main.bundlePath
        guard !isTranslocated else { return false }
        let inApplications = path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard inApplications else { return false }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parent)
    }

    /// macOS App Translocation runs quarantined unsigned apps from a random
    /// read-only path; self-update is impossible from there.
    var isTranslocated: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/private/var/folders/")
    }

    /// Set when the running copy can't update itself, so the UI can say why.
    var installLocationAdvice: String? {
        if isTranslocated {
            return tr("Move FAL Studio into your Applications folder to enable updates (it is currently running from a temporary quarantine copy).",
                      "請將 FAL Studio 移到「應用程式」資料夾才能更新（目前是從暫存的隔離副本執行）。")
        }
        if !Bundle.main.bundlePath.hasPrefix("/Applications/")
            && !Bundle.main.bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return tr("Drag FAL Studio into your Applications folder to enable in-place updates.",
                      "請將 FAL Studio 拖到「應用程式」資料夾，才能就地更新。")
        }
        return nil
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

    /// A newer build in this machine's own build folder. Requires: a recorded
    /// dev path, a replaceable install location, and a different bundle than
    /// the one running.
    private func localUpdate() -> Availability? {
        guard canSelfReplace, let devPath = devBuildPath else { return nil }
        let devURL = URL(fileURLWithPath: devPath)
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

    /// Replace the running app with this machine's dev build and relaunch.
    /// Copies to a staging path first and only swaps if that succeeds, so a
    /// failure can never leave the user with no app at all.
    func applyLocalUpdate() {
        guard canSelfReplace else {
            lastError = installLocationAdvice
                ?? tr("This copy of FAL Studio can't update itself in place.",
                      "此份 FAL Studio 無法就地更新。")
            return
        }
        guard let dev = devBuildPath else {
            lastError = tr("No local build found on this Mac.", "這台 Mac 上找不到本機建置版本。")
            return
        }
        let installed = Bundle.main.bundlePath
        let staging = installed + ".new"
        let backup = installed + ".old"
        // Staged swap: copy → move old aside → move new in → clean up.
        // If any step fails, restore the backup and reopen whatever survives.
        let script = """
        set -e
        sleep 0.7
        rm -rf "\(staging)" "\(backup)"
        cp -R "\(dev)" "\(staging)"
        mv "\(installed)" "\(backup)"
        if ! mv "\(staging)" "\(installed)"; then
            mv "\(backup)" "\(installed)"
            open "\(installed)"
            exit 1
        fi
        rm -rf "\(backup)"
        xattr -dr com.apple.quarantine "\(installed)" 2>/dev/null || true
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
