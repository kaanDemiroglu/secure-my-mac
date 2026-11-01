import Foundation
import IOKit
import IOKit.hid

/// Real accelerometer on Apple Silicon MacBooks (AppleSPUHIDDevice "accel").
/// Undocumented Apple interface: verified on MacBook Pro M2 Pro (Mac14,10), macOS 27.0.1, without root.
/// It may break on other models or future macOS versions, so availability and live data are always checked.
final class AppleSiliconMotionProvider: MotionProvider {
    var sensitivity: MotionSensitivity = .medium
    var onCalibrated: (@MainActor () -> Void)?
    /// Optional raw sample tap (x, y, z in g), called on the main thread. Used by diagnostics only.
    var onSample: ((Double, Double, Double) -> Void)?
    private(set) var sampleCount = 0
    /// Samples ignored right after start (about 8 s) so the lock screen, the hand leaving and the chair settle first.
    static let settleSamples = 800
    private(set) var calibratedAt: Date?
    private var lastPeak = 0.0
    /// For the event log: how big the movement was and how long after calibration it happened.
    var lastEventDetail: String {
        String(format: "%.3f g (%@), %.1f s after calibration", lastPeak, lastRule, Date().timeIntervalSince(calibratedAt ?? Date()))
            + (lastTraceName.map { ", trace \($0)" } ?? "")
    }
    private var lastRule = ""
    private var lastTraceName: String?
    /// Last ~5 s of raw samples, saved to disk when movement is detected so a false alarm can be analysed.
    private var trace: [(Double, Double, Double)] = []

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var detector = MotionDetector(sensitivity: .medium)
    private var handler: (@MainActor () -> Void)?
    private var driver: io_service_t = 0

    var isSimulation: Bool { false }

    var availability: MotionAvailability {
        let s = Self.accelDriver()
        defer { if s != 0 { IOObjectRelease(s) } }
        return s != 0 ? .available : .unavailable(reason: "No accelerometer found on this Mac.")
    }

    /// Caller must IOObjectRelease a non-zero result.
    static func accelDriver() -> io_service_t {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &it) == KERN_SUCCESS
        else { return 0 }
        defer { IOObjectRelease(it) }
        var s = IOIteratorNext(it)
        while s != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0)
            let d = props?.takeRetainedValue() as? [String: Any] ?? [:]
            if (d["dispatchAccel"] as? Bool) == true || (d["dispatchAccel"] as? Int) == 1 { return s }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return 0
    }

    private func setReporting(_ on: Bool) {
        guard driver != 0 else { return }
        let v: [(String, Int)] = on
            ? [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 10000)]
            : [("SensorPropertyReportingState", 0), ("SensorPropertyPowerState", 0), ("ReportInterval", 0)]
        for (k, n) in v { IORegistryEntrySetCFProperty(driver, k as CFString, NSNumber(value: n)) }
    }

    func start(onMotion: @escaping @MainActor () -> Void) {
        stop()
        handler = onMotion
        sampleCount = 0
        calibratedAt = nil
        trace = []
        lastTraceName = nil
        detector = MotionDetector(sensitivity: sensitivity)
        driver = Self.accelDriver()
        guard driver != 0 else { return }
        setReporting(true)

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3] as CFDictionary)
        IOHIDManagerOpen(mgr, 0)
        manager = mgr
        guard let dev = ((IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []).first(where: {
            "\(IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) ?? "" as CFString)" == "accel"
        }), IOHIDDeviceOpen(dev, 0) == kIOReturnSuccess else { return }
        device = dev
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        buffer = buf
        IOHIDDeviceRegisterInputReportCallback(dev, buf, 4096, { ctx, _, _, _, _, report, length in
            guard let ctx, length >= 18 else { return }
            Unmanaged<AppleSiliconMotionProvider>.fromOpaque(ctx).takeUnretainedValue().handle(report, length)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Report layout (verified): int32 little-endian X, Y, Z at byte offsets 6, 10, 14; divide by 65536 for g.
    private func handle(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        func axis(_ off: Int) -> Double {
            var v: Int32 = 0
            memcpy(&v, report + off, 4)
            return Double(Int32(littleEndian: v)) / 65536.0
        }
        sampleCount += 1
        let (x, y, z) = (axis(6), axis(10), axis(14))
        onSample?(x, y, z)
        trace.append((x, y, z))
        if trace.count > 500 { trace.removeFirst(trace.count - 500) }
        if sampleCount <= Self.settleSamples { return }
        switch detector.feed(x: x, y: y, z: z) {
        case .none: break
        case .calibrated: calibratedAt = Date(); let cb = onCalibrated; Task { @MainActor in cb?() }
        case .motion: lastPeak = detector.lastPeak; lastRule = detector.lastRule; saveTrace(); let h = handler; Task { @MainActor in h?() }
        }
    }

    /// Raw accelerometer numbers only (x, y, z in g), no personal data. Keeps the newest 5 files.
    private func saveTrace() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecureMyMac/traces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "HHmmss"
        let name = "trace-\(f.string(from: Date())).csv"
        let ref = detector.reference.map { String(format: "%.5f,%.5f,%.5f", $0.0, $0.1, $0.2) } ?? "none"
        var csv = "# reference x,y,z = \(ref); threshold = \(detector.threshold); rule = \(lastRule); 100 samples per second; last row = trigger\nx,y,z\n"
        for t in trace { csv += String(format: "%.5f,%.5f,%.5f\n", t.0, t.1, t.2) }
        try? csv.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        lastTraceName = name
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("trace-") }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }), files.count > 5 {
            for old in files.dropFirst(5) { try? FileManager.default.removeItem(at: old) }
        }
    }

    func stop() {
        if let dev = device {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(dev, 0)
        }
        if let m = manager { IOHIDManagerClose(m, 0) }
        device = nil; manager = nil
        buffer?.deallocate(); buffer = nil
        setReporting(false)
        if driver != 0 { IOObjectRelease(driver); driver = 0 }
        handler = nil
    }

    deinit { stop() }
}
