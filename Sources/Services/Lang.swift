import Foundation
import Observation

/// In-app UI language (independent of the macOS system language).
/// Settings → General has the picker; changes apply immediately.
@Observable
final class Lang {
    static let shared = Lang()

    var code: String {
        didSet { UserDefaults.standard.set(code, forKey: "appLanguage") }
    }

    private init() {
        code = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    var isChinese: Bool { code == "zh-Hant" }
}

/// Pick the UI string for the current language: `tr("Prompt", "提示詞")`.
func tr(_ english: String, _ chinese: String) -> String {
    Lang.shared.isChinese ? chinese : english
}

/// Localize the parameter chip labels defined in the model catalog.
func trParam(_ label: String) -> String {
    guard Lang.shared.isChinese else { return label }
    switch label {
    case "Aspect": return "寬高比"
    case "Resolution": return "解析度"
    case "Duration": return "長度"
    case "Audio": return "音訊"
    case "Quality": return "品質"
    case "Images": return "張數"
    default: return label
    }
}
