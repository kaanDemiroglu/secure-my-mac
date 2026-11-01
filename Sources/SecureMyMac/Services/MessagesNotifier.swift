import Foundation

enum MessagesError: Error { case invalidRecipient, timeout, failed(String) }

enum SendMode { case buddy, chat }   // buddy: via the iMessage service; chat: into the existing conversation

enum MessagesNotifier {
    /// The Apple ID the user types: any email address (iCloud, Gmail, Outlook, ...).
    static func isValidAppleID(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    static func isValidRecipient(_ s: String) -> Bool {
        s.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil
            || s.range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    private static let buddyScript = [
        "on run argv",
        "set theRecipient to item 1 of argv",
        "set theText to item 2 of argv",
        "tell application \"Messages\"",
        "set targetService to 1st service whose service type = iMessage",
        "set targetBuddy to buddy theRecipient of targetService",
        "send theText to targetBuddy",
        "end tell",
        "end run",
    ]

    private static let chatScript = [
        "on run argv",
        "set theRecipient to item 1 of argv",
        "set theText to item 2 of argv",
        "tell application \"Messages\"",
        "set theChat to chat id (\"any;-;\" & theRecipient)",
        "send theText to theChat",
        "end tell",
        "end run",
    ]

    /// Hands the text to Messages.app. Success means "Messages accepted it", NOT "iPhone received it".
    static func send(_ text: String, to recipient: String, mode: SendMode = .buddy, timeout: TimeInterval = 20) async throws {
        guard isValidRecipient(recipient) else { throw MessagesError.invalidRecipient }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = (mode == .buddy ? buddyScript : chatScript).flatMap { ["-e", $0] } + [recipient, text]
                let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
                do { try p.run() } catch { cont.resume(throwing: MessagesError.failed(error.localizedDescription)); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                p.waitUntilExit()
                let timedOut = killer.isCancelled == false && p.terminationReason == .uncaughtSignal
                killer.cancel()
                if timedOut { cont.resume(throwing: MessagesError.timeout); return }
                if p.terminationStatus == 0 { cont.resume() } else {
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "error"
                    cont.resume(throwing: MessagesError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }

    /// True when the account descriptions ("E:mail@x" / "P:+90...") include a phone number handle.
    static func hasPhoneHandle(in descriptions: String) -> Bool {
        descriptions.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("P:") }
    }

    /// Raw "E:mail@x,P:+90...," list of the iMessage accounts on this Mac, or nil if Messages could not be asked.
    static func accountDescriptions() async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global().async {
                let lines = ["tell application \"Messages\"", "set out to \"\"", "repeat with a in every account",
                             "try", "set out to out & (description of a) & \",\"", "end try", "end repeat", "return out", "end tell"]
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = lines.flatMap { ["-e", $0] }
                let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
                guard (try? p.run()) != nil else { cont.resume(returning: nil); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
                p.waitUntilExit(); killer.cancel()
                guard p.terminationStatus == 0 else { cont.resume(returning: nil); return }
                cont.resume(returning: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            }
        }
    }

    static func phoneRegistered() async -> Bool? { await accountDescriptions().map(hasPhoneHandle) }

    /// The user's own iMessage addresses (emails first, then phone numbers), without duplicates.
    static func parseAddresses(from descriptions: String) -> [String] {
        var emails: [String] = [], phones: [String] = []
        for part in descriptions.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespaces)
            guard t.count > 2 else { continue }
            let addr = String(t.dropFirst(2))
            guard isValidRecipient(addr) else { continue }
            if t.hasPrefix("E:"), !emails.contains(where: { $0.lowercased() == addr.lowercased() }) { emails.append(addr) }
            if t.hasPrefix("P:"), !phones.contains(addr) { phones.append(addr) }
        }
        return emails + phones
    }

    /// Try order: last working address, then the user's optional phone (only if iMessage knows it), then the Apple ID addresses.
    static func orderCandidates(phone: String?, phoneRegistered: Bool?, addresses: [String], preferred: String?) -> [String] {
        var out: [String] = []
        func add(_ a: String?) {
            guard let a, isValidRecipient(a), !out.contains(where: { $0.lowercased() == a.lowercased() }) else { return }
            out.append(a)
        }
        add(preferred)
        if let phone, phoneRegistered != false { add(phone) }
        addresses.forEach { add($0) }
        return Array(out.prefix(4))
    }
}
