import SwiftUI

struct MainView: View {
    @EnvironmentObject var loc: LocalizationManager
    @EnvironmentObject var c: ProtectionCoordinator
    @State private var showPin = false
    @State private var showSettings = false

    var body: some View {
        Group {
            if !c.hasPin { SetupView() } else { main }
        }
        .frame(width: 420)
        .onChange(of: c.state) { _, new in if new == .idle { showPin = false } }
        .sheet(isPresented: $showPin, onDismiss: { c.cancelVerify() }) {
            PinSheet(titleKey: c.alarmActive ? "btn.itWasMe" : "pin.title",
                     onSubmit: { pin in
                         let ok = c.verifyAndDisarm(pin)
                         if ok { showPin = false }
                         return ok
                     },
                     onCancel: { showPin = false })
                .environmentObject(loc)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(loc).environmentObject(c)
        }
    }

    private var statusKey: String {
        switch c.state {
        case .idle: return "status.idle"
        case .arming: return "status.arming"
        case .armed: return !c.sensorReady ? "status.arming" : (c.isArmedDemo ? "status.armedDemo" : "status.armed")
        case .alerting: return "status.alarm"
        case .verifyingOwner: return "status.verifying"
        }
    }

    private var descText: String {
        switch c.state {
        case .idle: return loc.t(c.lastOwnerConfirmed ? "desc.ownerConfirmed" : "desc.idle")
        case .arming: return loc.t("desc.arming", c.countdown)
        case .armed: return loc.t(!c.sensorReady ? "desc.calibrating" : (c.isArmedDemo ? "desc.armedDemo" : "desc.armed"))
        case .alerting: return loc.t("desc.alarm")
        case .verifyingOwner: return loc.t("desc.verifying")
        }
    }

    private var statusColor: Color {
        switch c.state {
        case .idle: return .secondary
        case .arming: return .orange
        case .armed: return c.sensorReady ? .green : .orange
        case .alerting, .verifyingOwner: return .red
        }
    }

    private var main: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(.tint)
                Text(verbatim: "Secure My Mac").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(loc.t("btn.settings"))
            }
            ShieldView(state: c.state == .armed && !c.sensorReady ? .arming : c.state).padding(.top, 6)
            Text(loc.t(statusKey)).font(.title2.bold()).foregroundStyle(statusColor)
            Text(descText).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(minHeight: 40)

            if let n = c.notice {
                Text(n.arg.map { loc.t(n.key, $0) } ?? loc.t(n.key))
                    .font(.caption).foregroundStyle(n.isError ? .red : .secondary)
                    .multilineTextAlignment(.center)
            }

            actions
        }
        .padding(24)
    }

    @ViewBuilder private var actions: some View {
        switch c.state {
        case .idle:
            Button(loc.t("btn.activate")) { c.activate() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button(loc.t(c.testAlarmRunning ? "btn.stopTestAlarm" : "btn.testAlarm")) { c.toggleTestAlarm() }
                .controlSize(.regular)
        case .arming:
            Button(loc.t("btn.cancel")) { c.cancelArming() }.controlSize(.large)
        case .armed:
            Button(loc.t("btn.deactivate")) { c.beginVerify(); showPin = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if c.isArmedDemo {
                Button(loc.t("btn.testTrigger")) { c.simulateTamper() }
                Button(loc.t("btn.testTriggerDelayed")) { c.simulateTamperDelayed() }
            }
        case .alerting, .verifyingOwner:
            Button { c.beginVerify(); showPin = true } label: {
                Text(loc.t("btn.itWasMe")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            Button(loc.t("btn.deactivate")) { c.beginVerify(); showPin = true }
        }
    }
}
