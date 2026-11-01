import Foundation
import SQLite3

struct IncomingMessage: Equatable { let rowID: Int64; let text: String }

struct OutgoingStatus: Equatable {
    let rowID: Int64; let isSent: Bool; let isDelivered: Bool; let error: Int
    var delivery: Delivery {
        if error != 0 { return .failed(error) }
        if isDelivered { return .delivered }
        return isSent ? .sent : .pending
    }
}

enum Delivery: Equatable {
    case delivered, sent, pending, unknown   // unknown: could not check (no Full Disk Access)
    case failed(Int)
}

enum RemoteReply {
    /// Accepts "Bendim1234" or "Bendim 1234" (also "Benim", "It was me", "ItWasMe"). Nothing else in between; digits alone are not accepted.
    static func parsePin(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard let re = try? NSRegularExpression(pattern: #"^(?:bendim|benim|it ?was ?me)\s*([0-9]{4,6})$"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t) else { return nil }
        return String(t[r])
    }

    /// Newer macOS keeps message text in `attributedBody` (typedstream) when `text` is NULL.
    static func decodeAttributedBody(_ d: Data) -> String? {
        guard let r = d.range(of: Data("NSString".utf8)) else { return nil }
        var i = r.upperBound + 5
        guard i < d.endIndex else { return nil }
        var len = Int(d[i]); i += 1
        if len == 0x81 {
            guard i + 2 <= d.endIndex else { return nil }
            len = Int(d[i]) | (Int(d[i + 1]) << 8); i += 2
        }
        guard len > 0, i + len <= d.endIndex else { return nil }
        return String(data: d[i..<(i + len)], encoding: .utf8)
    }
}

/// Read-only access to the Messages database. Needs Full Disk Access; `init` returns nil without it.
final class ChatDBReader {
    private var db: OpaquePointer?
    static var defaultPath: String { NSHomeDirectory() + "/Library/Messages/chat.db" }

    init?(path: String = ChatDBReader.defaultPath) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        guard maxRowID() != nil else { sqlite3_close(db); return nil }
    }
    deinit { sqlite3_close(db) }

    static func canAccess(path: String = ChatDBReader.defaultPath) -> Bool { ChatDBReader(path: path) != nil }

    func maxRowID() -> Int64? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(ROWID),0) FROM message", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : nil
    }

    /// Status of the newest message WE sent into this chat after `rowID`.
    func latestOutgoing(after rowID: Int64, chat: String) -> OutgoingStatus? {
        let sql = """
        SELECT m.ROWID, m.is_sent, m.is_delivered, m.error FROM message m
        JOIN chat_message_join j ON j.message_id = m.ROWID
        JOIN chat c ON c.ROWID = j.chat_id
        WHERE m.ROWID > ? AND m.is_from_me = 1 AND lower(c.chat_identifier) = lower(?)
        ORDER BY m.ROWID DESC LIMIT 1
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, rowID)
        sqlite3_bind_text(st, 2, chat, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return OutgoingStatus(rowID: sqlite3_column_int64(st, 0), isSent: sqlite3_column_int(st, 1) != 0,
                              isDelivered: sqlite3_column_int(st, 2) != 0, error: Int(sqlite3_column_int(st, 3)))
    }

    /// Messages sent from any of the user's own devices (is_from_me = 1), in any chat.
    /// A reply typed on the iPhone shows up here whichever conversation it was typed into.
    func newMessagesFromMe(after rowID: Int64) -> [IncomingMessage] {
        let sql = "SELECT ROWID, text, attributedBody FROM message WHERE ROWID > ? AND is_from_me = 1 ORDER BY ROWID"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, rowID)
        var out: [IncomingMessage] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var text: String?
            if let c = sqlite3_column_text(st, 1) { text = String(cString: c) }
            if (text ?? "").isEmpty, let blob = sqlite3_column_blob(st, 2) {
                text = RemoteReply.decodeAttributedBody(Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 2))))
            }
            out.append(IncomingMessage(rowID: sqlite3_column_int64(st, 0), text: text ?? ""))
        }
        return out
    }

    func newMessages(after rowID: Int64, chat: String) -> [IncomingMessage] {
        let sql = """
        SELECT m.ROWID, m.text, m.attributedBody FROM message m
        JOIN chat_message_join j ON j.message_id = m.ROWID
        JOIN chat c ON c.ROWID = j.chat_id
        WHERE m.ROWID > ? AND lower(c.chat_identifier) = lower(?)
        ORDER BY m.ROWID
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, rowID)
        sqlite3_bind_text(st, 2, chat, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var out: [IncomingMessage] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var text: String?
            if let c = sqlite3_column_text(st, 1) { text = String(cString: c) }
            if (text ?? "").isEmpty, let blob = sqlite3_column_blob(st, 2) {
                text = RemoteReply.decodeAttributedBody(Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 2))))
            }
            out.append(IncomingMessage(rowID: sqlite3_column_int64(st, 0), text: text ?? ""))
        }
        return out
    }
}
