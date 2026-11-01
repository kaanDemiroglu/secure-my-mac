import Foundation

enum MotionSensitivity: String, CaseIterable, Identifiable {
    case low, medium, high, max
    var id: String { rawValue }
    var labelKey: String { "sens.\(rawValue)" }
    /// Deviation from the resting reference, in g, that counts as movement.
    var threshold: Double {
        switch self { case .low: return 0.30; case .medium: return 0.15; case .high: return 0.07; case .max: return 0.02 }
    }
}

/// Pure logic (no hardware): calibrate on a still reference, then flag a LIFT (not a slide, a shake or a small tilt).
///
/// The reference is the resting gravity vector `b`. Each sample's deviation along gravity is the SIGNED vertical
/// value `v`. Lifting a Mac pushes it the same way for a few hundred milliseconds, so the 0.2 s average of `v`
/// stays away from zero. Shaking the table, knocks and dragging swing both ways, so that average cancels to
/// about zero (measured on real recordings: lifts 0.075 to 0.19 g, shake / slide / diagonal pull at most 0.007 g).
/// Two rules (see SPEC.md):
/// - vertical: the 0.2 s average of `v` is above the sensitivity threshold in 8 of the last 20 samples;
/// - tilt: the AVERAGE acceleration vector of the last 0.5 s is turned away from the reference by more than the
///   tilt limit (15 degrees at the highest sensitivity). Averaging cancels sideways shaking, so only a Mac that is
///   really held tilted (a slow lift) counts.
/// Sideways movement alone never alarms. While quiet the reference follows very slow drift, and a Mac that settles
/// somewhere new and stays completely still for 3 s becomes the new reference.
struct MotionDetector {
    enum Event: Equatable { case none, calibrated, motion }

    static let calibrationCount = 100       // about 1 second at 100 Hz: a sliding window of the latest samples
    static let checkEvery = 10              // stillness is checked every 10 samples (0.1 s) to save CPU
    static let quickCalibrationCount = 40   // about 0.4 s: used once, at the moment the screen locks
    static let smoothWindow = 20            // vertical rule: average of the last 0.2 s ...
    static let smoothSpan = 20              // ... checked over the last 20 averages ...
    static let smoothRequired = 8           // ... of which this many must be above the threshold
    static let tiltWindow = 50              // tilt rule: average vector of the last 0.5 s
    static let resettleCount = 300          // 3 s of complete stillness makes the new pose the reference
    static let resettleTolerance = 0.01     // g: what "completely still" means for that
    static let adapt = 1.0 / 300.0

    var threshold: Double
    /// Tilt (degrees) of the 0.5 s average vector that counts as lifted.
    var tiltLimit: Double

    private var samples: [(Double, Double, Double)] = []
    private var baseline: (Double, Double, Double)?
    private var recent: [(Double, Double, Double)] = []   // last 3 s, for the "settled somewhere new" check
    private var verticals: [Double] = []     // signed v of the last 20 samples
    private var verticalSum = 0.0
    private var over: [Bool] = []            // was the 0.2 s average above the threshold (last 20 averages)
    private var overCount = 0
    private var vectors: [(Double, Double, Double)] = []   // last 50 samples
    private var vectorSum = (0.0, 0.0, 0.0)
    private var sinceCheck = 0               // samples since the last stillness check (checked every 10, not every sample)
    /// The 0.2 s average vertical value (g) that triggered the last motion event.
    private(set) var lastPeak = 0.0
    /// Which rule fired last: "vertical" or "tilt NN°".
    private(set) var lastRule = ""

    init(sensitivity: MotionSensitivity) {
        threshold = sensitivity.threshold
        switch sensitivity { case .low: tiltLimit = 45; case .medium: tiltLimit = 30; case .high: tiltLimit = 20; case .max: tiltLimit = 15 }
    }

    var isCalibrated: Bool { baseline != nil }
    var reference: (Double, Double, Double)? { baseline }

    mutating func reset() { samples = []; baseline = nil; recent = []; clearWindows(); sinceCheck = 0 }

    private mutating func clearWindows() {
        verticals = []; verticalSum = 0; over = []; overCount = 0; vectors = []; vectorSum = (0, 0, 0)
    }

    /// Sliding window: the newest `calibrationCount` samples. As soon as they are all still, they become the
    /// reference. Movement never restarts the count, so the sensor is ready right after the Mac stops being touched.
    mutating func feed(x: Double, y: Double, z: Double) -> Event {
        guard var b = baseline else {
            samples.append((x, y, z))
            if samples.count > Self.calibrationCount { samples.removeFirst(samples.count - Self.calibrationCount) }
            sinceCheck += 1
            if samples.count >= Self.calibrationCount, sinceCheck >= Self.checkEvery {
                sinceCheck = 0
                if let m = stillMean(of: samples, tolerance: threshold * 0.5) { baseline = m; samples = []; recent = []; clearWindows(); return .calibrated }
            }
            return .none
        }

        let nb = (b.0 * b.0 + b.1 * b.1 + b.2 * b.2).squareRoot()
        guard nb > 0 else { return .none }
        // Signed deviation along gravity.
        let v = ((x - b.0) * b.0 + (y - b.1) * b.1 + (z - b.2) * b.2) / nb

        // Vertical rule: 0.2 s average of the signed value (running sums, no per-sample scans).
        verticals.append(v); verticalSum += v
        if verticals.count > Self.smoothWindow { verticalSum -= verticals.removeFirst() }
        var average = 0.0
        if verticals.count == Self.smoothWindow {
            average = verticalSum / Double(Self.smoothWindow)
            let isOver = abs(average) > threshold
            over.append(isOver); if isOver { overCount += 1 }
            if over.count > Self.smoothSpan, over.removeFirst() { overCount -= 1 }
        }
        if overCount >= Self.smoothRequired { return fire(rule: "vertical", peak: abs(average)) }

        // Tilt rule: angle between the 0.5 s average vector and the reference.
        vectors.append((x, y, z)); vectorSum = (vectorSum.0 + x, vectorSum.1 + y, vectorSum.2 + z)
        if vectors.count > Self.tiltWindow { let o = vectors.removeFirst(); vectorSum = (vectorSum.0 - o.0, vectorSum.1 - o.1, vectorSum.2 - o.2) }
        if vectors.count == Self.tiltWindow {
            let n = Double(Self.tiltWindow)
            let m = (vectorSum.0 / n, vectorSum.1 / n, vectorSum.2 / n)
            let nm = (m.0 * m.0 + m.1 * m.1 + m.2 * m.2).squareRoot()
            if nm > 0 {
                let cosT = min(1, max(-1, (m.0 * b.0 + m.1 * b.1 + m.2 * b.2) / (nm * nb)))
                let angle = acos(cosT) * 180 / .pi
                if angle >= tiltLimit { return fire(rule: String(format: "tilt %.0f°", angle), peak: abs(average)) }
            }
        }

        // The Mac settled somewhere new (after a slide or a small tilt) and has been completely still for 3 s: new reference.
        recent.append((x, y, z))
        if recent.count > Self.resettleCount { recent.removeFirst(recent.count - Self.resettleCount) }
        sinceCheck += 1
        if recent.count == Self.resettleCount, sinceCheck >= Self.checkEvery {
            sinceCheck = 0
            if let m = stillMean(of: recent, tolerance: Self.resettleTolerance), Self.dist(m, b) > 0.003 {
                baseline = m; clearWindows(); return .none
            }
        }
        if Self.dist((x, y, z), b) < threshold {  // quiet: follow very slow drift
            b.0 += (x - b.0) * Self.adapt; b.1 += (y - b.1) * Self.adapt; b.2 += (z - b.2) * Self.adapt
            baseline = b
        }
        return .none
    }

    private mutating func fire(rule: String, peak: Double) -> Event {
        lastPeak = peak; lastRule = rule
        clearWindows()
        return .motion
    }

    /// Mean of the samples if they are all within `tolerance` of it (the Mac is still), otherwise nil.
    private func stillMean(of window: [(Double, Double, Double)], tolerance: Double) -> (Double, Double, Double)? {
        let n = Double(window.count)
        guard n > 0 else { return nil }
        let m = (window.map { $0.0 }.reduce(0, +) / n,
                 window.map { $0.1 }.reduce(0, +) / n,
                 window.map { $0.2 }.reduce(0, +) / n)
        let worst = window.map { Self.dist($0, m) }.max() ?? 0
        return worst > tolerance ? nil : m
    }

    /// Called when the screen locks and the sensor is not calibrated yet: if the last ~0.4 s were still,
    /// use them as the reference now, so a movement right after the lock is not missed.
    mutating func calibrateNow() -> Bool {
        guard baseline == nil, samples.count >= Self.quickCalibrationCount,
              let m = stillMean(of: Array(samples.suffix(Self.quickCalibrationCount)), tolerance: threshold * 0.5) else { return false }
        baseline = m; samples = []; recent = []; clearWindows()
        return true
    }

    private static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dx = a.0 - b.0, dy = a.1 - b.1, dz = a.2 - b.2
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
