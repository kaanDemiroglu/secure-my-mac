import Foundation

/// Sends an iMessage and, when Full Disk Access allows, checks what Messages did with it.
/// A failed message is retried once through the existing conversation.
@MainActor
enum MessageDelivery {
    static func sendVerified(_ text: String, to recipient: String) async throws -> Delivery {
        let reader = ChatDBReader()                       // nil without Full Disk Access
        var baseline = reader?.maxRowID() ?? 0
        try await MessagesNotifier.send(text, to: recipient, mode: .buddy)
        guard let reader else { return .unknown }
        var result = await wait(reader, chat: recipient, after: baseline)
        if case .failed = result {
            baseline = reader.maxRowID() ?? baseline
            if (try? await MessagesNotifier.send(text, to: recipient, mode: .chat)) != nil {
                result = await wait(reader, chat: recipient, after: baseline)
            }
        }
        return result
    }

    /// Delivered/failed end the wait at once; "sent" without confirmation counts after 6 s
    /// (normal when messaging yourself). Gives up after 20 s.
    static func wait(_ reader: ChatDBReader, chat: String, after baseline: Int64, timeout: TimeInterval = 20) async -> Delivery {
        let deadline = Date().addingTimeInterval(timeout)
        var sentSince: Date?
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let st = reader.latestOutgoing(after: baseline, chat: chat) else { continue }
            switch st.delivery {
            case .delivered, .failed: return st.delivery
            case .sent:
                sentSince = sentSince ?? Date()
                if Date().timeIntervalSince(sentSince!) > 6 { return .sent }
            default: sentSince = nil
            }
        }
        return .pending
    }
}
