import Foundation
import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private var tables: [String: [String: String]] = [:]

    init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// "en" or "tr"
    var effective: String { Self.effectiveCode(for: language) }

    nonisolated static func effectiveCode(for language: AppLanguage) -> String {
        switch language {
        case .en: return "en"
        case .tr: return "tr"
        case .system:
            let first = Locale.preferredLanguages.first ?? "en"
            return first.hasPrefix("tr") ? "tr" : "en"
        }
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let code = effective
        if tables[code] == nil { tables[code] = AppResources.strings(language: code) }
        var s = tables[code]?[key] ?? tables["en"]?[key] ?? key
        if tables["en"] == nil { tables["en"] = AppResources.strings(language: "en") }
        if s == key { s = tables["en"]?[key] ?? key }
        return args.isEmpty ? s : String(format: s, arguments: args)
    }
}

/// Message texts are built at send time in the language currently selected.
@MainActor
enum MessageTemplates {
    static func alarmDetected(replyHint: Bool = false) -> String {
        let base = LocalizationManager.shared.t("msg.alarm")
        return replyHint ? base + "\n" + LocalizationManager.shared.t("msg.alarmReplyHint") : base
    }
    static func ownerVerified() -> String { LocalizationManager.shared.t("msg.ownerVerified") }
    static func test() -> String { LocalizationManager.shared.t("msg.test") }
}
