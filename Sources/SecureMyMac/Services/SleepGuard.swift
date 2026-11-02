import Foundation

/// Kapak kapalıyken pilde de uyumamak için `pmset disablesleep` ayarını açıp kapatır.
/// Yönetici parolası ister (macOS'un kendi parola penceresi). Kalıcı kök servisi kurmaz.
/// Ayar açık kalırsa Mac kapalı kapakla uyumaz; bu yüzden her zaman geri alınmalıdır.
enum SleepGuard {
    /// Şu an "uyuma" ayarı açık mı? (yetki gerektirmez)
    static func isDisabled() async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["-g"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            guard (try? p.run()) != nil else { return false }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            return text.split(separator: "\n").contains {
                let parts = $0.split(whereSeparator: { $0 == " " || $0 == "\t" })
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
        }.value
    }

    /// Ayarı açar/kapatır. Kullanıcı parola penceresini iptal ederse veya hata olursa false döner.
    /// `prompt`: parola penceresinde görünen açıklama (tırnak ve ters bölü içermemeli).
    static func set(disabled: Bool, prompt: String) async -> Bool {
        let safePrompt = prompt.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "")
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with prompt \"\(safePrompt)\" with administrator privileges"
        let ok: Bool = await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
        guard ok else { return false }
        return await isDisabled() == disabled
    }
}
