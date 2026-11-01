import Foundation

/// idle -> arming -> armed -> alerting -> verifyingOwner -> idle
enum ProtectionState: Equatable {
    case idle, arming, armed, alerting, verifyingOwner
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, tr
    var id: String { rawValue }
    var labelKey: String { "lang.\(rawValue)" }
}

struct Notice: Equatable {
    var key: String
    var arg: String? = nil
    var isError = false
}
