import SwiftUI

struct SetupView: View {
    @EnvironmentObject var loc: LocalizationManager
    @EnvironmentObject var c: ProtectionCoordinator
    @State private var pin = ""
    @State private var pin2 = ""
    @State private var errorKey: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.system(size: 60, weight: .light)).foregroundStyle(.tint)
            Text(loc.t("setup.title")).font(.title2.bold())
            Text(loc.t("setup.subtitle")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SecureField(loc.t("setup.pin"), text: $pin).textFieldStyle(.roundedBorder).frame(width: 220)
            SecureField(loc.t("setup.pinConfirm"), text: $pin2).textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit(create)
            if let k = errorKey { Text(loc.t(k)).font(.caption).foregroundStyle(.red) }
            Button(loc.t("setup.create"), action: create).buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
    }

    private func create() {
        guard PinStore.isValidFormat(pin) else { errorKey = "setup.length"; return }
        guard pin == pin2 else { errorKey = "setup.mismatch"; return }
        if !c.createPin(pin) { errorKey = "setup.failed" }
    }
}
