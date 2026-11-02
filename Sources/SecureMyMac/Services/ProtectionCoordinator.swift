import Foundation
import SwiftUI

@MainActor
final class ProtectionCoordinator: ObservableObject {
    static let shared = ProtectionCoordinator()

    @Published private(set) var state: ProtectionState = .idle
    /// Countdown in seconds. Fixed at 5 (no setting); tests may shorten it.
    static let defaultArmDelay = 5
    @Published private(set) var countdown = 5
    @Published private(set) var hasPin: Bool
    @Published private(set) var testAlarmRunning = false
    /// False while the real sensor is still settling/calibrating: nothing is being watched yet.
    @Published private(set) var sensorReady = false
    @Published private(set) var lastOwnerConfirmed = false
    @Published var notice: Notice?

    @Published var demoMode: Bool { didSet { UserDefaults.standard.set(demoMode, forKey: "demoMode") } }
    @Published var lockOnArm: Bool { didSet { UserDefaults.standard.set(lockOnArm, forKey: "lockOnArm") } }
    /// Kapak kapalıyken pilde de uyumasın (pmset, yönetici parolası ister). Varsayılan kapalı.
    @Published var keepAwakeLidClosed: Bool { didSet { UserDefaults.standard.set(keepAwakeLidClosed, forKey: "keepAwakeLidClosed") } }
    /// Ayarı biz açtık ve henüz geri almadık; uygulama yeniden açılınca tekrar denenir.
    private var sleepRestoreNeeded: Bool {
        get { UserDefaults.standard.bool(forKey: "sleepRestoreNeeded") }
        set { UserDefaults.standard.set(newValue, forKey: "sleepRestoreNeeded") }
    }
    @Published var sendOnAlarm: Bool { didSet { UserDefaults.standard.set(sendOnAlarm, forKey: "sendOnAlarm") } }
    var armDelay = ProtectionCoordinator.defaultArmDelay
    @Published var sensitivity: MotionSensitivity { didSet { UserDefaults.standard.set(sensitivity.rawValue, forKey: "sensitivity") } }
    @Published var remoteReply: Bool { didSet { UserDefaults.standard.set(remoteReply, forKey: "remoteReply") } }
    @Published var recipient: String { didSet { UserDefaults.standard.set(recipient, forKey: "recipient") } }

    let log: EventLog
    private(set) var pinStore: PinStore
    let alarm: AlarmPlayer
    private let hardware = AppleSiliconMotionProvider()
    private let simulation = SimulationMotionProvider()
    private let lidGuard = LidGuard()
    private var activeProvider: MotionProvider?
    private var countdownTask: Task<Void, Never>?
    private var stateBeforeVerify: ProtectionState = .armed
    private var demoActive = false

    // Separate flags so nothing is logged or sent twice.
    private var alarmTriggered = false
    private var messageSent = false
    /// The Apple ID the alarm message went to; the follow-up goes to the same one even if settings change.
    private var alertRecipient: String?
    private var remoteTask: Task<Void, Never>?

    var alarmActive: Bool { alarmTriggered }
    var loc: LocalizationManager { .shared }
    var hardwareAvailable: Bool { hardware.availability == .available }

    init(pinStore: PinStore = PinStore(storage: KeychainStorage()), log: EventLog? = nil, alarm: AlarmPlayer? = nil) {
        self.pinStore = pinStore
        self.alarm = alarm ?? AlarmPlayer()
        self.log = log ?? EventLog()
        hasPin = pinStore.hasPin
        let d = UserDefaults.standard
        // Demo mode is the default only when this Mac has no real accelerometer.
        let hasSensor = AppleSiliconMotionProvider().availability == .available
        demoMode = d.object(forKey: "demoMode") as? Bool ?? !hasSensor
        lockOnArm = d.bool(forKey: "lockOnArm")           // off until the user opts in
        sendOnAlarm = d.bool(forKey: "sendOnAlarm")
        keepAwakeLidClosed = d.bool(forKey: "keepAwakeLidClosed")   // off until the user opts in
        var saved = d.string(forKey: "recipient") ?? ""
        if !MessagesNotifier.isValidAppleID(saved) { saved = ""; d.removeObject(forKey: "recipient") }   // old phone numbers are dropped
        recipient = saved
        d.removeObject(forKey: "armDelay")                 // the countdown setting was removed
        sensitivity = MotionSensitivity(rawValue: d.string(forKey: "sensitivity") ?? "") ?? .max
        remoteReply = d.bool(forKey: "remoteReply")       // off until the user opts in
        if d.bool(forKey: "sleepRestoreNeeded") {
            // Önceki oturumda ayar açık kalmış. Pencere hazır olsun, kullanıcı nedenini görsün, sonra parola iste.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.state == .idle else { return }
                self.notice = Notice(key: "notice.keepAwakeRestoring")
                await self.restoreSleepIfNeeded()
            }
        }
    }

    // MARK: Uyku ayarı (pmset)

    /// Parola penceresi veya pmset çağrısı sürüyor mu? Aynı anda iki işlem çalışmaz.
    private var sleepBusy = false
    /// Çıkış sırasında beklenmesi gereken bir uyku ayarı işi var mı?
    var sleepWorkPending: Bool { sleepRestoreNeeded || sleepBusy }

    private func enableKeepAwake() async {
        guard !sleepBusy else { return }
        sleepBusy = true
        sleepRestoreNeeded = true   // önce işaretle: parola penceresi açıkken koruma kapanırsa da geri alınsın
        let ok = await SleepGuard.set(disabled: true, prompt: loc.t("prompt.keepAwakeOn"))
        sleepBusy = false
        if ok {
            log.add("keepAwakeOn")
        } else {
            if await !SleepGuard.isDisabled() { sleepRestoreNeeded = false }
            log.add("keepAwakeFailed"); notice = Notice(key: "notice.keepAwakeFailed", isError: true)
        }
        // Parola girilirken koruma çoktan kapandıysa ayarı hemen geri al.
        if state == .idle { await restoreSleepIfNeeded() }
    }

    /// Ayar açık kaldıysa ve koruma aktif değilse geri alır. Başarısızsa kullanıcıya gösterir.
    func restoreSleepIfNeeded() async {
        guard sleepRestoreNeeded, state == .idle, !sleepBusy else { return }
        sleepBusy = true
        defer { sleepBusy = false }
        if await !SleepGuard.isDisabled() { sleepRestoreNeeded = false; return }
        if await SleepGuard.set(disabled: false, prompt: loc.t("prompt.keepAwakeOff")) {
            sleepRestoreNeeded = false; log.add("keepAwakeOff")
        } else {
            log.add("keepAwakeRestoreFailed"); notice = Notice(key: "notice.keepAwakeRestoreFailed", isError: true)
        }
    }

    /// Çıkıştan önce: süren/gereken uyku ayarı işini bitirir (en çok 60 sn bekler).
    func finishSleepWorkBeforeQuit() async {
        var waited = 0.0
        while sleepBusy, waited < 60 { try? await Task.sleep(nanoseconds: 200_000_000); waited += 0.2 }
        await restoreSleepIfNeeded()
    }

    var isArmedDemo: Bool { state != .idle && state != .arming && demoActive }

    // MARK: PIN

    func createPin(_ pin: String) -> Bool {
        guard pinStore.setPin(pin) else { return false }
        hasPin = true
        log.add("pinSet")
        return true
    }

    func changePin(old: String, new: String) -> Bool {
        guard pinStore.verify(old) else { log.add("wrongPin"); return false }
        guard pinStore.setPin(new) else { return false }
        log.add("pinChanged")
        return true
    }

    // MARK: Arming

    func activate() {
        guard state == .idle else { return }
        guard hasPin else { notice = Notice(key: "notice.noPin", isError: true); return }
        let provider: MotionProvider
        if demoMode { provider = simulation; demoActive = true }
        else if hardware.availability == .available { provider = hardware; demoActive = false }
        else {
            notice = Notice(key: "notice.sensorUnavailable", isError: true)
            log.add("armFailed", detail: "sensor")
            return
        }
        notice = nil
        lastOwnerConfirmed = false
        alarmTriggered = false
        messageSent = false
        state = .arming
        let delay = armDelay
        countdown = delay
        sensorReady = provider.isSimulation
        // The sensor starts together with the countdown: it settles and calibrates while the countdown runs,
        // so it is already watching the moment the screen locks. Motion during the countdown never alarms
        // (tamperDetected only reacts while armed).
        startMonitoring(provider, countdown: delay)
        countdownTask = Task { [weak self] in
            for n in stride(from: delay, through: 1, by: -1) {
                self?.countdown = n
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            self?.finishArming(with: provider)
        }
    }

    private func startMonitoring(_ provider: MotionProvider, countdown delay: Int) {
        hardware.sensitivity = sensitivity
        hardware.settleSamples = AppleSiliconMotionProvider.settleSamples(forCountdown: delay)
        hardware.onCalibrated = { [weak self] in
            // A callback queued before Cancel/Deactivate must not mark an idle app as ready.
            guard let self, self.state == .arming || self.state == .armed else { return }
            self.sensorReady = true; self.log.add("calibrated")
        }
        hardware.alarmEnabled = false
        provider.start { [weak self] in
            guard let self else { return }
            if !provider.isSimulation, self.state == .armed { self.log.add("motion", detail: self.hardware.lastEventDetail) }
            self.tamperDetected()
        }
        activeProvider = provider
    }

    func cancelArming() {
        guard state == .arming else { return }
        countdownTask?.cancel()
        activeProvider?.stop(); activeProvider = nil
        sensorReady = false
        state = .idle
        log.add("armCancelled")
    }

    private func finishArming(with provider: MotionProvider) {
        guard state == .arming else { return }
        // A real sensor that stayed silent during the whole countdown must never be shown as "protected",
        // and the screen is not locked in that case.
        if !provider.isSimulation, provider.sampleCount == 0 {
            provider.stop(); activeProvider = nil
            sensorReady = false
            state = .idle
            log.add("sensorNoData")
            notice = Notice(key: "notice.sensorNoData", isError: true)
            return
        }
        if provider === hardware { hardware.calibrateNow(); hardware.alarmEnabled = true }   // watching from the very moment the screen locks
        state = .armed
        log.add(demoActive ? "armedDemo" : "armed")
        alarm.prewarm()
        startLidGuard()
        if keepAwakeLidClosed { Task { await enableKeepAwake() } }
        if lockOnArm { lockScreen() }
    }

    private func lockScreen() {
        let sent = ScreenLocker.lock()
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if ScreenLocker.isLocked {
                log.add("lockOk"); notice = Notice(key: "notice.lockOk")
            } else if sent {
                log.add("lockFailed", detail: "unverified"); notice = Notice(key: "notice.lockUnverified", isError: true)
            } else {
                log.add("lockFailed"); notice = Notice(key: "notice.lockFailed", isError: true)
            }
        }
    }

    // MARK: Alarm

    /// Demo button. Works only while demo-armed.
    func simulateTamper() {
        guard state == .armed, demoActive else { return }
        log.add("simTrigger")
        simulation.simulate()
    }

    /// Demo only: simulated tamper after a delay, so the screen can be locked first.
    func simulateTamperDelayed(seconds: Double = 15) {
        guard state == .armed, demoActive else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.simulateTamper()
        }
    }

    /// Kapak kapanınca hemen alarm; uykudan uyanınca alarm hâlâ aktifse sesi yeniden başlat.
    private func startLidGuard() {
        lidGuard.onLidClosed = { [weak self] lidClosed in
            guard let self, self.state == .armed else { return }
            self.log.add(lidClosed ? "lidClosed" : "sleepWhileArmed")
            self.tamperDetected()
        }
        lidGuard.onWake = { [weak self] in
            guard let self, self.state == .alerting || self.state == .verifyingOwner, self.alarmTriggered,
                  !self.alarm.isPlaying else { return }
            self.alarm.play()
        }
        lidGuard.start()
    }

    private func tamperDetected() {
        guard state == .armed, !alarmTriggered else { return }
        alarmTriggered = true
        state = .alerting
        alarm.play()
        if alarm.usedFallback { notice = Notice(key: "notice.alarmFileMissing", isError: true) }
        log.add("alarm")
        // Alarm sound already started; the message never delays it.
        if sendOnAlarm, !messageSent, channelReady {
            messageSent = true
            let to = recipient.trimmingCharacters(in: .whitespaces)
            alertRecipient = to
            let hint = remoteReply
            Task { await sendMessage(MessageTemplates.alarmDetected(replyHint: hint), to: to, updateNotice: false) }
            if remoteReply { startRemoteListening(imessageChat: to) }
        }
    }

    // MARK: Owner verification

    func beginVerify() {
        guard state == .armed || state == .alerting else { return }
        stateBeforeVerify = state
        state = .verifyingOwner
    }

    func cancelVerify() {
        guard state == .verifyingOwner else { return }
        state = stateBeforeVerify
    }

    /// Correct PIN: stop alarm, protection off. Wrong PIN: nothing changes.
    func verifyAndDisarm(_ pin: String) -> Bool {
        guard state == .verifyingOwner || state == .armed || state == .alerting else { return false }
        guard pinStore.verify(pin) else { log.add("wrongPin"); return false }
        let wasAlert = alarmTriggered || stateBeforeVerify == .alerting
        alarm.stop()
        lidGuard.stop()
        remoteTask?.cancel(); remoteTask = nil
        activeProvider?.stop(); activeProvider = nil
        let shouldFollowUp = alarmTriggered && sendOnAlarm
        let followUpTo = alertRecipient ?? recipient.trimmingCharacters(in: .whitespaces)
        alertRecipient = nil
        alarmTriggered = false
        messageSent = false
        demoActive = false
        lastOwnerConfirmed = wasAlert
        state = .idle
        sensorReady = false
        log.add(wasAlert ? "ownerConfirmed" : "disarmed")
        if sleepRestoreNeeded { Task { await restoreSleepIfNeeded() } }
        if shouldFollowUp {
            Task { await sendMessage(MessageTemplates.ownerVerified(), to: followUpTo, updateNotice: false, isFollowUp: true) }
        }
        return true
    }

    // MARK: Remote "It Was Me" (reply from iPhone)

    var chatAccessAvailable: Bool { ChatDBReader.canAccess() }

    /// Only while the alarm is on; replies must be "Bendim<PIN>"; max 3 wrong PINs, then replies are locked.
    /// Returns true when listening should stop.
    private func handleRemotePin(_ pin: String, wrong: inout Int) -> Bool {
        if verifyAndDisarm(pin) { log.add("remoteReply", detail: "ok"); return true }
        wrong += 1
        log.add("remoteReply", detail: "wrong")
        if wrong >= 3 { log.add("remoteLocked"); return true }
        return false
    }

    private func startRemoteListening(imessageChat chat: String) {
        remoteTask?.cancel()
        remoteTask = Task { [weak self] in
            guard let reader = ChatDBReader(), var baseline = reader.maxRowID() else {
                self?.log.add("remoteUnavailable")
                self?.notice = Notice(key: "notice.remoteNoAccess", isError: true)
                return
            }
            var chats = (await MessagesNotifier.accountDescriptions()).map(MessagesNotifier.parseAddresses) ?? []
            if MessagesNotifier.isValidAppleID(chat) { chats.append(chat) }
            self?.log.add("remoteListening", detail: "\(Set(chats.map { $0.lowercased() }).count) addresses")
            var wrong = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled, self.state == .alerting || self.state == .verifyingOwner else { return }
                // Replies typed on the iPhone (is_from_me) in any chat, plus anything arriving in the user's own address chats.
                var found = reader.newMessagesFromMe(after: baseline)
                for c in Set(chats.map { $0.lowercased() }) { found += reader.newMessages(after: baseline, chat: c) }
                var seen = Set<Int64>()
                let fresh = found.filter { seen.insert($0.rowID).inserted }.sorted { $0.rowID < $1.rowID }
                guard !fresh.isEmpty else { continue }
                baseline = max(baseline, fresh.map { $0.rowID }.max() ?? baseline)
                let pins = fresh.compactMap { RemoteReply.parsePin($0.text) }
                // Counts only, never the message text.
                self.log.add("remoteSeen", detail: "\(fresh.count) new, \(pins.count) match")
                for pin in pins { if self.handleRemotePin(pin, wrong: &wrong) { return } }
            }
        }
    }

    // MARK: Notifications (iMessage)

    var recipientValid: Bool { MessagesNotifier.isValidAppleID(recipient.trimmingCharacters(in: .whitespaces)) }
    /// iMessage needs the Apple ID email the user typed.
    var channelReady: Bool { recipientValid }

    func sendTestMessage() async {
        guard channelReady else { notice = Notice(key: "notice.noRecipient", isError: true); return }
        await sendMessage(MessageTemplates.test(), to: recipient.trimmingCharacters(in: .whitespaces), updateNotice: true)
    }

    private func sendMessage(_ text: String, to: String, updateNotice: Bool, isFollowUp: Bool = false) async {
        log.add("messageAttempt", detail: "imessage")
        do {
            guard MessagesNotifier.isValidAppleID(to) else {
                log.add("messageFailed", detail: "no address")
                notice = Notice(key: "notice.noRecipient", isError: true)
                return
            }
            let result = try await MessageDelivery.sendVerified(text, to: to)
            handleDelivery(result, updateNotice: updateNotice, isFollowUp: isFollowUp)
        } catch {
            log.add("messageFailed", detail: "\(error)")
            if updateNotice { notice = Notice(key: "notice.messageFailed", arg: "\(error)", isError: true) }
            else if isFollowUp { notice = Notice(key: "notice.followupUncertain", isError: true) }
            else { notice = Notice(key: "notice.messageFailed", arg: "\(error)", isError: true) }
        }
    }

    /// Success is only announced on a test; a failure or doubt is always shown on the main screen.
    private func handleDelivery(_ d: Delivery, updateNotice: Bool, isFollowUp: Bool) {
        switch d {
        case .delivered:
            log.add("messageDelivery", detail: "delivered")
            if updateNotice { notice = Notice(key: "notice.imessageDelivered") }
        case .sent:
            log.add("messageDelivery", detail: "sent")
            if updateNotice { notice = Notice(key: "notice.imessageSent") }
        case .unknown:
            log.add("messageDelivery", detail: "unchecked")
            if updateNotice { notice = Notice(key: "notice.messageHanded") }
        case .pending:
            log.add("messageDelivery", detail: "pending")
            notice = Notice(key: "notice.imessagePending", isError: true)
        case .failed(let code):
            log.add("messageFailed", detail: "code \(code)")
            notice = Notice(key: "notice.imessageFailed", arg: "\(code)", isError: true)
        }
    }

    // MARK: Test alarm

    func toggleTestAlarm() {
        guard state == .idle else { return }
        if testAlarmRunning { alarm.stop(); testAlarmRunning = false; return }
        testAlarmRunning = true
        log.add("testAlarm")
        alarm.playTest { [weak self] in self?.testAlarmRunning = false }
    }
}
