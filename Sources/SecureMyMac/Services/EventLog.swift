import Foundation

struct LogEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var code: String      // language independent, e.g. "alarm"
    var detail: String?
}

@MainActor
final class EventLog: ObservableObject {
    @Published private(set) var events: [LogEvent] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SecureMyMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("events.json")
        }
        if let d = try? Data(contentsOf: self.fileURL),
           let e = try? JSONDecoder().decode([LogEvent].self, from: d) { events = e }
    }

    func add(_ code: String, detail: String? = nil) {
        events.insert(LogEvent(date: Date(), code: code, detail: detail), at: 0)
        if events.count > 200 { events.removeLast(events.count - 200) }
        if let d = try? JSONEncoder().encode(events) { try? d.write(to: fileURL, options: .atomic) }
    }
}
