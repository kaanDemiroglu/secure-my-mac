import XCTest
@testable import SecureMyMac

final class PinStoreTests: XCTestCase {
    func testSetAndVerify() {
        let s = PinStore(storage: MemoryStorage())
        XCTAssertFalse(s.hasPin)
        XCTAssertTrue(s.setPin("1234"))
        XCTAssertTrue(s.hasPin)
        XCTAssertTrue(s.verify("1234"))
        XCTAssertFalse(s.verify("1235"))
        XCTAssertFalse(s.verify(""))
    }
    func testFormatRejected() {
        let s = PinStore(storage: MemoryStorage())
        for bad in ["123", "1234567", "12a4", "", "١٢٣٤"] { XCTAssertFalse(s.setPin(bad), bad) }
    }
    func testStoredValueIsNotPlainPin() {
        let m = MemoryStorage(); let s = PinStore(storage: m)
        XCTAssertTrue(s.setPin("4321"))
        XCTAssertEqual(m.read()?.count, 48)
        XCTAssertNil(m.read()?.range(of: Data("4321".utf8)))
    }
}

final class LocalizationTests: XCTestCase {
    func testKeysMatchAndNoEmptyValues() {
        let en = AppResources.strings(language: "en"), tr = AppResources.strings(language: "tr")
        XCTAssertFalse(en.isEmpty); XCTAssertFalse(tr.isEmpty)
        XCTAssertEqual(Set(en.keys), Set(tr.keys), "en/tr key mismatch")
        for (k, v) in en { XCTAssertFalse(v.isEmpty, k) }
        for (k, v) in tr { XCTAssertFalse(v.isEmpty, k) }
    }
    func testFormatSpecifiersMatch() {
        let en = AppResources.strings(language: "en"), tr = AppResources.strings(language: "tr")
        for (k, v) in en {
            let a = v.components(separatedBy: "%").count, b = (tr[k] ?? "").components(separatedBy: "%").count
            XCTAssertEqual(a, b, k)
        }
    }
    func testEffectiveLanguage() {
        XCTAssertEqual(LocalizationManager.effectiveCode(for: .en), "en")
        XCTAssertEqual(LocalizationManager.effectiveCode(for: .tr), "tr")
    }
    func testRequiredMessages() {
        let en = AppResources.strings(language: "en"), tr = AppResources.strings(language: "tr")
        XCTAssertEqual(en["msg.test"], "Secure My Mac: This is a test notification.")
        XCTAssertEqual(tr["msg.test"], "Secure My Mac: Bu bir test bildirimidir.")
        XCTAssertEqual(tr["btn.itWasMe"], "Bendim")
    }
}

final class RecipientTests: XCTestCase {
    func testValidation() {
        XCTAssertTrue(MessagesNotifier.isValidRecipient("+905551234567"))
        XCTAssertTrue(MessagesNotifier.isValidRecipient("a.b@icloud.com"))
        XCTAssertFalse(MessagesNotifier.isValidRecipient("05551234567"))
        XCTAssertFalse(MessagesNotifier.isValidRecipient("abc"))
        XCTAssertFalse(MessagesNotifier.isValidRecipient("+90 555\"; do shell script"))
    }
}

@MainActor
final class FlowTests: XCTestCase {
    func make() -> ProtectionCoordinator {
        let a = AlarmPlayer(); a.muted = true
        let log = EventLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("smm-\(UUID()).json"))
        let c = ProtectionCoordinator(pinStore: PinStore(storage: MemoryStorage()), log: log, alarm: a)
        c.demoMode = true; c.lockOnArm = false; c.sendOnAlarm = false; c.armDelay = 3
        XCTAssertTrue(c.createPin("2468"))
        return c
    }
    func armed() async -> ProtectionCoordinator {
        let c = make()
        c.activate()
        XCTAssertEqual(c.state, .arming)
        try? await Task.sleep(nanoseconds: 3_400_000_000)
        XCTAssertEqual(c.state, .armed)
        return c
    }

    func testNeverArmsWithoutAnySensor() {
        let c = make(); c.demoMode = false
        c.activate()
        if c.hardwareAvailable {
            XCTAssertEqual(c.state, .arming)           // real sensor present: arming starts
            c.cancelArming()
        } else {
            XCTAssertEqual(c.state, .idle)
            XCTAssertEqual(c.notice?.key, "notice.sensorUnavailable")
        }
        XCTAssertEqual(c.state, .idle)
    }
    func testCancelCountdown() {
        let c = make(); c.activate(); c.cancelArming()
        XCTAssertEqual(c.state, .idle)
    }
    func testCountdownIsFixedAtFiveSeconds() {
        UserDefaults.standard.set(20, forKey: "armDelay")                 // an old saved choice must be ignored
        defer { UserDefaults.standard.removeObject(forKey: "armDelay") }
        let c = ProtectionCoordinator(pinStore: PinStore(storage: MemoryStorage()),
                                      log: EventLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("smm-\(UUID()).json")),
                                      alarm: AlarmPlayer())
        XCTAssertEqual(c.armDelay, 5)
        XCTAssertEqual(ProtectionCoordinator.defaultArmDelay, 5)
    }
    func testSettleLeavesTheLastTwoSecondsForCalibration() {
        for (delay, settle) in [(3, 100), (5, 300), (10, 800), (20, 800)] {
            XCTAssertEqual(AppleSiliconMotionProvider.settleSamples(forCountdown: delay), settle, "delay \(delay)")
        }
    }
    func testMotionDuringCountdownDoesNotAlarm() async {
        let c = make()
        c.activate()
        XCTAssertEqual(c.state, .arming)
        c.simulateTamper()                        // only works when armed: ignored while arming
        XCTAssertEqual(c.state, .arming)
        XCTAssertFalse(c.alarmActive)
        c.cancelArming()
    }
    func testItWasMeFlow() async {
        let c = await armed()
        c.simulateTamper()
        XCTAssertEqual(c.state, .alerting)
        c.simulateTamper()                       // second event must not re-trigger
        XCTAssertEqual(c.log.events.filter { $0.code == "alarm" }.count, 1)
        c.beginVerify()
        XCTAssertEqual(c.state, .verifyingOwner)
        XCTAssertFalse(c.verifyAndDisarm("0000"))   // wrong PIN: alarm stays
        XCTAssertEqual(c.state, .verifyingOwner)
        c.cancelVerify()
        XCTAssertEqual(c.state, .alerting)
        c.beginVerify()
        XCTAssertTrue(c.verifyAndDisarm("2468"))
        XCTAssertEqual(c.state, .idle)              // no auto re-arm
        XCTAssertTrue(c.lastOwnerConfirmed)
        XCTAssertTrue(c.log.events.contains { $0.code == "ownerConfirmed" })
        XCTAssertTrue(c.log.events.contains { $0.code == "wrongPin" })
    }
    func testDeactivateNeedsPin() async {
        let c = await armed()
        XCTAssertFalse(c.verifyAndDisarm("1111"))
        XCTAssertEqual(c.state, .armed)
        XCTAssertTrue(c.verifyAndDisarm("2468"))
        XCTAssertEqual(c.state, .idle)
        XCTAssertTrue(c.log.events.contains { $0.code == "disarmed" })
    }
    func testSimulateIgnoredWhenNotArmed() {
        let c = make(); c.simulateTamper()
        XCTAssertEqual(c.state, .idle)
    }
}

import SQLite3

final class RemoteReplyTests: XCTestCase {
    func testParsePin() {
        XCTAssertEqual(RemoteReply.parsePin("Bendim 1234"), "1234")
        XCTAssertEqual(RemoteReply.parsePin("BENDİM123456"), "123456")
        XCTAssertEqual(RemoteReply.parsePin("bendim2468"), "2468")
        XCTAssertEqual(RemoteReply.parsePin("ItWasMe1234"), "1234")
        XCTAssertEqual(RemoteReply.parsePin("It was me 1234"), "1234")
        XCTAssertEqual(RemoteReply.parsePin("it was me 2468"), "2468")
        XCTAssertEqual(RemoteReply.parsePin("  Bendim 2468 \n"), "2468")
        XCTAssertNil(RemoteReply.parsePin("2468"))              // keyword required
        XCTAssertNil(RemoteReply.parsePin("Bendim: 2468"))      // nothing in between
        XCTAssertNil(RemoteReply.parsePin("Bendim"))
        XCTAssertNil(RemoteReply.parsePin("Bendim 123"))
        XCTAssertNil(RemoteReply.parsePin("1234567"))
        XCTAssertNil(RemoteReply.parsePin("ben bendim 1234"))
        XCTAssertNil(RemoteReply.parsePin("Secure My Mac: Güvenlik uyarısı!"))
    }
    func testDecodeAttributedBody() {
        var d = Data([0x04, 0x0B]) + Data("streamtyped".utf8) + Data([0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84])
        d += Data("NSAttributedString".utf8) + Data([0x00, 0x84, 0x84]) + Data("NSObject".utf8) + Data([0x00, 0x85, 0x92, 0x84, 0x84, 0x84])
        d += Data("NSString".utf8) + Data([0x01, 0x94, 0x84, 0x01, 0x2B, 11]) + Data("Bendim 1234".utf8) + Data([0x86])
        XCTAssertEqual(RemoteReply.decodeAttributedBody(d), "Bendim 1234")
        XCTAssertNil(RemoteReply.decodeAttributedBody(Data("nothing".utf8)))
    }
    func testReaderFiltersChatAndRowID() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID()).db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE message(ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB);
        CREATE TABLE chat(ROWID INTEGER PRIMARY KEY, chat_identifier TEXT);
        CREATE TABLE chat_message_join(chat_id INTEGER, message_id INTEGER);
        INSERT INTO chat VALUES (1,'me@icloud.com'),(2,'other@icloud.com');
        INSERT INTO message VALUES (1,'old 1111',NULL),(2,'Bendim 2468',NULL),(3,'Bendim 9999',NULL);
        INSERT INTO chat_message_join VALUES (1,1),(1,2),(2,3);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let r = try XCTUnwrap(ChatDBReader(path: path))
        XCTAssertEqual(r.maxRowID(), 3)
        XCTAssertEqual(r.newMessages(after: 1, chat: "ME@iCloud.com"), [IncomingMessage(rowID: 2, text: "Bendim 2468")])
        XCTAssertTrue(r.newMessages(after: 3, chat: "me@icloud.com").isEmpty)
        XCTAssertNil(ChatDBReader(path: "/nonexistent/chat.db"))
    }
    @MainActor func testAlarmMessageTemplates() {
        let en = AppResources.strings(language: "en")
        XCTAssertEqual(MessageTemplates.alarmDetected(replyHint: false), LocalizationManager.shared.t("msg.alarm"))
        XCTAssertTrue(MessageTemplates.alarmDetected(replyHint: true).contains("\n"))
        XCTAssertNotNil(en["msg.alarmReplyHint"])
    }
}

final class MotionDetectorTests: XCTestCase {
    private func calibrated(_ sens: MotionSensitivity = .medium) -> MotionDetector {
        var d = MotionDetector(sensitivity: sens)
        var last = MotionDetector.Event.none
        for i in 0..<MotionDetector.calibrationCount {
            last = d.feed(x: 0.001 * Double(i % 3), y: 0.004, z: -0.98)
        }
        XCTAssertEqual(last, .calibrated)
        return d
    }
    private func rest(_ d: inout MotionDetector, _ n: Int) {
        for i in 0..<n { XCTAssertEqual(d.feed(x: 0.001 * Double(i % 3), y: 0.004, z: -0.98), .none) }
    }
    func testQuietSensorNeverTriggers() {
        var d = calibrated(.max)
        for i in 0..<5000 { XCTAssertEqual(d.feed(x: 0.002 * Double(i % 5), y: 0.004, z: -0.98 + 0.003 * Double(i % 4)), .none) }
    }
    func testLoneBlipIgnoredButShortStrongMovementTriggers() {
        var d = calibrated()
        for _ in 0..<(MotionDetector.requiredOver - 1) { XCTAssertEqual(d.feed(x: 0.5, y: 0, z: -0.98), .none) }
        rest(&d, MotionDetector.windowSize + 5)                                  // blip slides out
        var fired = false
        for _ in 0..<MotionDetector.requiredOver { if d.feed(x: 0.5, y: 0, z: -0.98) == .motion { fired = true } }
        XCTAssertTrue(fired)
    }
    func testMaxSensitivityIgnoresShortSmallBumpsLikeTheFalseAlarms() {
        var d = calibrated(.max)
        // 0.025 g and 0.035 g bumps for a few samples (what the false alarms looked like) must NOT fire
        for amp in [0.025, 0.035, 0.05] {
            for _ in 0..<8 { XCTAssertEqual(d.feed(x: amp, y: 0.004, z: -0.98), .none) }
            rest(&d, 60)
        }
    }
    func testMaxSensitivityCatchesLastingSlightTilt() {
        var d = calibrated(.max)
        var fired = false
        for _ in 0..<MotionDetector.weakWindowSize { if d.feed(x: 0.03, y: 0.004, z: -0.98) == .motion { fired = true } }   // about 1.7 degrees, kept
        XCTAssertTrue(fired)
        XCTAssertEqual(d.lastRule, "weak")
    }
    func testBigQuickMovementFiresStrongRuleAtMax() {
        var d = calibrated(.max)
        var fired = false
        for _ in 0..<MotionDetector.requiredOver { if d.feed(x: 0.3, y: 0.004, z: -0.98) == .motion { fired = true } }
        XCTAssertTrue(fired)
        XCTAssertEqual(d.lastRule, "strong")
    }
    func testSlowSettlingIsAbsorbed() {
        var d = calibrated(.max)
        // 0.03 g drift over 10 seconds (1000 samples): the Mac slowly settling, not a theft
        for i in 0..<1000 { XCTAssertEqual(d.feed(x: 0.03 * Double(i) / 1000, y: 0.004, z: -0.98), .none, "sample \(i)") }
    }
    func testSmallTiltBelowThresholdIgnoredOnLowSensitivity() {
        var d = calibrated(.low)
        for _ in 0..<500 { XCTAssertEqual(d.feed(x: 0.12, y: 0.004, z: -0.98), .none) }
    }
    func testPeakOfTriggeringWindowIsReported() {
        var d = calibrated(.max)
        for _ in 0..<MotionDetector.requiredOver { _ = d.feed(x: 0.2, y: 0.004, z: -0.98) }
        XCTAssertEqual(d.lastPeak, 0.2, accuracy: 0.02)
    }
    func testCalibratesRightAfterTheMacStopsMoving() {
        var d = MotionDetector(sensitivity: .max)
        for i in 0..<300 { _ = d.feed(x: i % 2 == 0 ? 0.6 : -0.6, y: 0, z: -0.98) }     // hand still on the Mac
        XCTAssertFalse(d.isCalibrated)
        var ready = -1
        for i in 0..<(MotionDetector.calibrationCount + 30) where ready < 0 {
            if d.feed(x: 0.001 * Double(i % 3), y: 0.004, z: -0.98) == .calibrated { ready = i + 1 }
        }
        XCTAssertGreaterThan(ready, 0)
        XCTAssertLessThanOrEqual(ready, MotionDetector.calibrationCount + MotionDetector.checkEvery)   // about 1 s after it stopped
    }
    func testCalibrateNowAtLockUsesTheLastStillMoment() {
        var d = MotionDetector(sensitivity: .max)
        for i in 0..<60 { _ = d.feed(x: i % 2 == 0 ? 0.6 : -0.6, y: 0, z: -0.98) }
        for i in 0..<MotionDetector.quickCalibrationCount { _ = d.feed(x: 0.001 * Double(i % 3), y: 0.004, z: -0.98) }
        XCTAssertFalse(d.isCalibrated)                                                 // normal window not full yet
        XCTAssertTrue(d.calibrateNow())
        XCTAssertTrue(d.isCalibrated)
        var fired = false
        for _ in 0..<MotionDetector.requiredOver { if d.feed(x: 0.3, y: 0.004, z: -0.98) == .motion { fired = true } }
        XCTAssertTrue(fired)                                                           // movement right after the lock is caught
    }
    func testCalibrateNowRefusesWhileStillMoving() {
        var d = MotionDetector(sensitivity: .max)
        for i in 0..<80 { _ = d.feed(x: i % 2 == 0 ? 0.6 : -0.6, y: 0, z: -0.98) }
        XCTAssertFalse(d.calibrateNow())
        XCTAssertFalse(d.isCalibrated)
    }
    func testResetDropsAnOutdatedReference() {
        var d = calibrated(.max)
        XCTAssertTrue(d.isCalibrated)
        d.reset()
        XCTAssertFalse(d.isCalibrated)                                                 // the countdown restarts calibration after a movement
        var ready = false
        for i in 0..<(MotionDetector.calibrationCount + MotionDetector.checkEvery) { if d.feed(x: 0.001 * Double(i % 3), y: 0.004, z: -0.98) == .calibrated { ready = true } }
        XCTAssertTrue(ready)
    }
    func testMovingDuringCalibrationRestartsIt() {
        var d = MotionDetector(sensitivity: .medium)
        for i in 0..<MotionDetector.calibrationCount { XCTAssertEqual(d.feed(x: i % 2 == 0 ? 0.6 : -0.6, y: 0, z: -0.98), .none) }
        XCTAssertFalse(d.isCalibrated)
    }
}

final class DeliveryTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(OutgoingStatus(rowID: 1, isSent: true, isDelivered: true, error: 0).delivery, .delivered)
        XCTAssertEqual(OutgoingStatus(rowID: 1, isSent: true, isDelivered: false, error: 0).delivery, .sent)
        XCTAssertEqual(OutgoingStatus(rowID: 1, isSent: false, isDelivered: false, error: 0).delivery, .pending)
        XCTAssertEqual(OutgoingStatus(rowID: 1, isSent: false, isDelivered: false, error: 22).delivery, .failed(22))
        XCTAssertEqual(OutgoingStatus(rowID: 1, isSent: true, isDelivered: true, error: 4).delivery, .failed(4))
    }
    func testReaderFindsOnlyOurNewestOutgoingInThatChat() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID()).db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE message(ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, is_from_me INT, is_sent INT, is_delivered INT, error INT);
        CREATE TABLE chat(ROWID INTEGER PRIMARY KEY, chat_identifier TEXT);
        CREATE TABLE chat_message_join(chat_id INTEGER, message_id INTEGER);
        INSERT INTO chat VALUES (1,'+905551112233'),(2,'other@icloud.com');
        INSERT INTO message VALUES (1,'old',NULL,1,1,1,0),(2,'ours',NULL,1,0,0,22),(3,'echo',NULL,0,1,1,0),(4,'elsewhere',NULL,1,1,1,0);
        INSERT INTO chat_message_join VALUES (1,1),(1,2),(1,3),(2,4);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let r = try XCTUnwrap(ChatDBReader(path: path))
        XCTAssertEqual(r.latestOutgoing(after: 1, chat: "+905551112233")?.delivery, .failed(22))
        XCTAssertNil(r.latestOutgoing(after: 2, chat: "+905551112233"))   // only the incoming echo is newer
        XCTAssertEqual(r.latestOutgoing(after: 0, chat: "OTHER@icloud.com")?.delivery, .delivered)
    }
}

final class PhoneHandleTests: XCTestCase {
    func testDetectsPhoneHandle() {
        XCTAssertFalse(MessagesNotifier.hasPhoneHandle(in: "E:a@icloud.com,missing value,E:b@icloud.com,"))
        XCTAssertTrue(MessagesNotifier.hasPhoneHandle(in: "E:a@icloud.com, P:+905551112233,"))
        XCTAssertFalse(MessagesNotifier.hasPhoneHandle(in: ""))
    }
}

final class AddressTests: XCTestCase {
    func testParseAddressesEmailsFirstDedupedAndFiltered() {
        let d = "E:Me@icloud.com,missing value,E:me@icloud.com,E:work@mac.com,P:+905551112233,P:+905551112233,E:not an email,"
        XCTAssertEqual(MessagesNotifier.parseAddresses(from: d), ["Me@icloud.com", "work@mac.com", "+905551112233"])
        XCTAssertEqual(MessagesNotifier.parseAddresses(from: ""), [])
    }
    func testCandidateOrder() {
        let addrs = ["a@icloud.com", "b@icloud.com"]
        // preferred first, then registered phone, then own addresses; no duplicates
        XCTAssertEqual(MessagesNotifier.orderCandidates(phone: "+905551112233", phoneRegistered: true, addresses: addrs, preferred: "b@icloud.com"),
                       ["b@icloud.com", "+905551112233", "a@icloud.com"])
        // phone that iMessage does not know is skipped
        XCTAssertEqual(MessagesNotifier.orderCandidates(phone: "+905551112233", phoneRegistered: false, addresses: addrs, preferred: nil), addrs)
        // no phone given: just the Apple ID addresses
        XCTAssertEqual(MessagesNotifier.orderCandidates(phone: nil, phoneRegistered: nil, addresses: addrs, preferred: nil), addrs)
        XCTAssertEqual(MessagesNotifier.orderCandidates(phone: nil, phoneRegistered: nil, addresses: [], preferred: nil), [])
    }
}

final class FromMeTests: XCTestCase {
    func testNewMessagesFromMeAnyChatOnlyOutgoingAfterBaseline() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID()).db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE message(ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, is_from_me INT);
        INSERT INTO message VALUES (1,'old',NULL,1),(2,'Bendim2468',NULL,1),(3,'Bendim9999',NULL,0),(4,NULL,NULL,1);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let r = try XCTUnwrap(ChatDBReader(path: path))
        XCTAssertEqual(r.newMessagesFromMe(after: 1).map { $0.rowID }, [2, 4])      // incoming #3 is not "from me"
        XCTAssertEqual(r.newMessagesFromMe(after: 1).first?.text, "Bendim2468")
    }
}

final class AppleIDTests: XCTestCase {
    func testAnyEmailProviderIsAccepted() {
        for ok in ["a@icloud.com", "ali.veli@gmail.com", "x_y+z@outlook.com", "me@hotmail.co.uk", "kaan@sirket.com.tr"] {
            XCTAssertTrue(MessagesNotifier.isValidAppleID(ok), ok)
        }
        for bad in ["", "+905551112233", "05551112233", "abc", "a@b", "a b@c.com", "a@c.com; rm"] {
            XCTAssertFalse(MessagesNotifier.isValidAppleID(bad), bad)
        }
    }
}

@MainActor
final class PinChangeTests: XCTestCase {
    func testChangePinNeedsOldPinAndSwitchesToNew() {
        let a = AlarmPlayer(); a.muted = true
        let log = EventLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("smm-\(UUID()).json"))
        let c = ProtectionCoordinator(pinStore: PinStore(storage: MemoryStorage()), log: log, alarm: a)
        XCTAssertTrue(c.createPin("1111"))
        XCTAssertFalse(c.changePin(old: "9999", new: "2222"))      // wrong old PIN
        XCTAssertFalse(c.changePin(old: "1111", new: "12"))        // bad format
        XCTAssertTrue(c.pinStore.verify("1111"))                   // nothing changed
        XCTAssertTrue(c.changePin(old: "1111", new: "2222"))
        XCTAssertTrue(c.pinStore.verify("2222"))
        XCTAssertFalse(c.pinStore.verify("1111"))
        XCTAssertTrue(c.log.events.contains { $0.code == "pinChanged" })
    }
}
