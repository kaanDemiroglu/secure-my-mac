import SwiftUI

struct PinSheet: View {
    @EnvironmentObject var loc: LocalizationManager
    let titleKey: String
    let onSubmit: (String) -> Bool
    let onCancel: () -> Void
    @State private var pin = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.system(size: 34)).foregroundStyle(.tint)
            Text(loc.t(titleKey)).font(.headline)
            SecureField(loc.t("pin.prompt"), text: $pin)
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .multilineTextAlignment(.center)
                .onSubmit(submit)
                .accessibilityLabel(loc.t("pin.title"))
            if wrong { Text(loc.t("pin.wrong")).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(loc.t("btn.cancel"), role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(loc.t("btn.confirm"), action: submit).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(pin.isEmpty)
            }
        }
        .padding(24).frame(width: 300)
    }

    private func submit() {
        if onSubmit(pin) { return }
        wrong = true; pin = ""
    }
}

struct ShieldView: View {
    let state: ProtectionState
    var color: Color {
        switch state {
        case .idle: return .gray
        case .arming: return .orange
        case .armed: return .green
        case .alerting, .verifyingOwner: return .red
        }
    }
    var symbol: String {
        switch state {
        case .idle: return "shield"
        case .arming: return "shield.lefthalf.filled"
        case .armed: return "checkmark.shield.fill"
        case .alerting, .verifyingOwner: return "exclamationmark.shield.fill"
        }
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 92, weight: .light))
            .foregroundStyle(color.gradient)
            .symbolEffect(.pulse, isActive: state == .alerting)
            .accessibilityHidden(true)
    }
}
