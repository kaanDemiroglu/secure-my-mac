import Foundation

/// Finds resource files inside the .app bundle, or in the repo's Resources folder when run with `swift run`.
enum AppResources {
    static var devRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    static func url(_ name: String, ext: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        let dev = devRoot.appendingPathComponent("\(name).\(ext)")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func strings(language: String) -> [String: String] {
        var candidates: [URL] = []
        if let u = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                   subdirectory: nil, localization: language) { candidates.append(u) }
        candidates.append(devRoot.appendingPathComponent("\(language).lproj/Localizable.strings"))
        for u in candidates {
            if let d = NSDictionary(contentsOf: u) as? [String: String] { return d }
        }
        return [:]
    }
}
