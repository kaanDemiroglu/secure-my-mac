import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting while protection is on would silently drop protection; require PIN deactivation first.
        MainActor.assumeIsolated { ProtectionCoordinator.shared.state == .idle ? .terminateNow : .terminateCancel }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Set by the app once SwiftUI is ready; opens the main window when it was closed.
    static var openMainWindow: (() -> Void)?

    /// Clicking the Dock icon while no window is visible (the window was closed, the app keeps running) shows the window again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showMainWindow() }
        return true
    }

    /// Brings the existing main window forward, or asks SwiftUI to open a new one.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "Secure My Mac" && $0.canBecomeMain }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}

@main
struct SecureMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var loc = LocalizationManager.shared
    @StateObject private var coordinator = ProtectionCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Secure My Mac", id: "main") {
            MainView()
                .environmentObject(loc)
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            Text(statusText)
            Divider()
            Button(loc.t("menu.open")) { AppDelegate.showMainWindow() }
            Button(coordinator.state == .idle ? loc.t("menu.quit") : loc.t("menu.quitBlocked")) {
                NSApp.terminate(nil)
            }.disabled(coordinator.state != .idle)
        } label: {
            Image(systemName: menuSymbol)
                .onAppear { AppDelegate.openMainWindow = { openWindow(id: "main") } }
        }
    }

    private var menuSymbol: String {
        switch coordinator.state {
        case .idle: return "shield"
        case .arming: return "shield.lefthalf.filled"
        case .armed: return "checkmark.shield.fill"
        case .alerting, .verifyingOwner: return "exclamationmark.shield.fill"
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle: return loc.t("status.idle")
        case .arming: return loc.t("status.arming")
        case .armed: return loc.t(coordinator.isArmedDemo ? "status.armedDemo" : "status.armed")
        case .alerting: return loc.t("status.alarm")
        case .verifyingOwner: return loc.t("status.verifying")
        }
    }
}
