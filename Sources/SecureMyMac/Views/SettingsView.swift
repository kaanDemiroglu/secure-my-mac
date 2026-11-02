import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var loc: LocalizationManager
    @EnvironmentObject var c: ProtectionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSend = false
    @State private var oldPin = ""
    @State private var newPin = ""
    @State private var newPin2 = ""
    @State private var pinMessageIsError = false
    @State private var pinMessage: String?
    @State private var addresses: [String] = []

    private func changePin() {
        pinMessageIsError = true
        if oldPin.isEmpty || newPin.isEmpty || newPin2.isEmpty { pinMessage = loc.t("pin.fillAll"); return }
        if !PinStore.isValidFormat(newPin) { pinMessage = loc.t("setup.length") }
        else if newPin != newPin2 { pinMessage = loc.t("setup.mismatch") }
        else if c.changePin(old: oldPin, new: newPin) { pinMessage = loc.t("pin.changed"); pinMessageIsError = false }
        else { pinMessage = loc.t("pin.wrong") }
        oldPin = ""; newPin = ""; newPin2 = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(loc.t("settings.title")).font(.title3.bold())
                Spacer()
                Button(loc.t("btn.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Form {
                Picker(loc.t("settings.language"), selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { Text(loc.t($0.labelKey)).tag($0) }
                }

                Section(loc.t("settings.pin")) {
                    SecureField(loc.t("pin.oldPin"), text: $oldPin, prompt: Text(loc.t("pin.oldPin")))
                        .textFieldStyle(.roundedBorder)
                    SecureField(loc.t("pin.newPin"), text: $newPin, prompt: Text(loc.t("pin.newPin")))
                        .textFieldStyle(.roundedBorder)
                    SecureField(loc.t("pin.newPinAgain"), text: $newPin2, prompt: Text(loc.t("pin.newPinAgain")))
                        .textFieldStyle(.roundedBorder)
                    Button(loc.t("btn.changePin")) { changePin() }
                    if let m = pinMessage {
                        Text(m).font(.caption).foregroundStyle(pinMessageIsError ? .red : .green)
                    }
                }

                Section(loc.t("settings.notifications")) {
                    LabeledContent(loc.t("settings.channel"), value: loc.t("channel.imessage"))
                    TextField(loc.t("settings.recipient"), text: $c.recipient,
                              prompt: Text(loc.t("settings.recipientPlaceholder")))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .accessibilityLabel(loc.t("settings.recipient"))
                    if c.recipient.isEmpty, !addresses.isEmpty {
                        HStack {
                            Text(loc.t("settings.suggested")).font(.caption).foregroundStyle(.secondary)
                            ForEach(addresses.filter { MessagesNotifier.isValidAppleID($0) }.prefix(3), id: \.self) { a in
                                Button(a) { c.recipient = a }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                    Toggle(loc.t("settings.sendOnAlarm"), isOn: $c.sendOnAlarm)
                    Toggle(loc.t("settings.remoteReply"), isOn: $c.remoteReply).disabled(!c.sendOnAlarm)
                    Button(loc.t("btn.testMessage")) { confirmSend = true }.disabled(!c.channelReady)
                    if let n = c.notice, n.key.hasPrefix("notice.message") || n.key.hasPrefix("notice.imessage")
                        || n.key.hasPrefix("notice.remote") || n.key == "notice.noRecipient" {
                        Text(n.arg.map { loc.t(n.key, $0) } ?? loc.t(n.key))
                            .font(.caption).foregroundStyle(n.isError ? .red : .secondary)
                    }
                }

                Section {
                    Toggle(loc.t("settings.demo"), isOn: $c.demoMode)
                    if c.hardwareAvailable {
                        Picker(loc.t("settings.sensitivity"), selection: $c.sensitivity) {
                            ForEach(MotionSensitivity.allCases) { Text(loc.t($0.labelKey)).tag($0) }
                        }
                    }
                    Toggle(loc.t("settings.lockOnArm"), isOn: $c.lockOnArm)
                    Toggle(loc.t("settings.keepAwake"), isOn: $c.keepAwakeLidClosed)
                    Text(loc.t("settings.keepAwakeHint")).font(.caption).foregroundStyle(.secondary)
                }

                Section(loc.t("settings.diagnostics")) {
                    LabeledContent(loc.t("diag.motion"),
                                   value: loc.t(c.hardwareAvailable ? "diag.motionYes" : "diag.motionNo"))
                    LabeledContent(loc.t("diag.chatAccess"),
                                   value: loc.t(c.chatAccessAvailable ? "diag.chatAccessYes" : "diag.chatAccessNo"))
                    LabeledContent(loc.t("diag.screenLock"),
                                   value: loc.t(ScreenLocker.isLocked ? "diag.screenLockNow" : "diag.screenLockNot"))
                }

                Section(loc.t("settings.log")) {
                    if c.log.events.isEmpty { Text(loc.t("settings.noEvents")).foregroundStyle(.secondary) }
                    ForEach(c.log.events.prefix(30)) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.date, format: .dateTime.hour().minute().second()).monospacedDigit()
                                .foregroundStyle(.secondary).font(.caption)
                            Text(loc.t("log.\(e.code)") + (e.detail.map { " (\($0))" } ?? "")).font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 620)
        .task { addresses = (await MessagesNotifier.accountDescriptions()).map(MessagesNotifier.parseAddresses) ?? [] }
        .confirmationDialog(loc.t("confirm.testMessage", c.recipient),
                            isPresented: $confirmSend) {
            Button(loc.t("confirm.send")) { Task { await c.sendTestMessage() } }
            Button(loc.t("btn.cancel"), role: .cancel) {}
        }
    }
}
