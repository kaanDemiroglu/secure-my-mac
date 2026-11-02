import Foundation
import AppKit
import IOKit
import IOKit.pwr_mgt

/// Koruma açıkken kapak kapanmasını ve uykuya geçişi izler.
/// - Şarjdayken "uyanık kal" kilidi tutar, böylece kapak kapalıyken de Mac uyumaz.
/// - Pilde macOS kapak kapanınca uykuyu zorla yapar; bu durumda uykudan hemen önce alarm tetiklenir.
/// Bu sınıf yetki istemez ve sistem ayarı değiştirmez (yalnızca IOKit uyku kilidi).
/// Pilde kapalı kapakta uyumamak için gereken yönetici yetkili `pmset` çağrısı ayrıdır: bkz. `SleepGuard`.
@MainActor
final class LidGuard {
    /// `lidClosed`: kapak gerçekten kapalıysa true; değilse (menüden uyut, pil bitti vb.) false.
    var onLidClosed: ((_ lidClosed: Bool) -> Void)?
    var onWake: (() -> Void)?

    private var timer: Timer?
    private var assertionID: IOPMAssertionID = 0
    private var observers: [NSObjectProtocol] = []
    private var lastClosed = false
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastClosed = Self.isLidClosed()
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Secure My Mac protection" as CFString, &assertionID)
        // Kapak kapalıyken de uyumasın (yalnızca şarjda etkilidir).
        var sysID: IOPMAssertionID = 0
        if IOPMAssertionCreateWithName("PreventSystemSleep" as CFString,
                                       IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                       "Secure My Mac lid-closed protection" as CFString, &sysID) == kIOReturnSuccess {
            systemSleepAssertion = sysID
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onLidClosed?(Self.isLidClosed()) }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let closed = Self.isLidClosed()
                if closed, !self.lastClosed { self.onLidClosed?(true) }
                self.lastClosed = closed
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate(); timer = nil
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
        if let s = systemSleepAssertion { IOPMAssertionRelease(s); systemSleepAssertion = nil }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private var systemSleepAssertion: IOPMAssertionID?

    /// IOPMrootDomain → AppleClamshellState (true = kapak kapalı). Okunamazsa "açık" sayılır.
    static func isLidClosed() -> Bool {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        guard let v = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return false }
        return (v as? Bool) ?? false
    }
}
