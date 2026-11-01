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

/// Pure logic (no hardware): calibrate on a still reference, then flag movement.
///
/// Two rules, so a short vibration does not set the alarm off but a real lift, slide or tilt does:
/// - strong: 3 of the last 10 samples (about 30 ms) above the strong threshold, which is the sensitivity
///   threshold but at least 0.06 g;
/// - weak: when the sensitivity threshold is below 0.06 g, 25 of the last 40 samples (about 0.4 s) above it.
///   A lasting offset (a tilt, a carried Mac) passes; a brief bump does not.
/// While quiet the reference follows very slow drift (time constant about 3 s), e.g. the Mac settling.
struct MotionDetector {
    enum Event: Equatable { case none, calibrated, motion }

    static let calibrationCount = 100       // about 1 second at 100 Hz: a sliding window of the latest samples
    static let quickCalibrationCount = 40   // about 0.4 s: used once, at the moment the screen locks
    static let windowSize = 10
    static let requiredOver = 3
    static let weakWindowSize = 40
    static let weakRequired = 25
    static let adapt = 1.0 / 300.0
    static let strongFloor = 0.06

    var threshold: Double
    var strongThreshold: Double { max(threshold, Self.strongFloor) }

    private var samples: [(Double, Double, Double)] = []
    private var baseline: (Double, Double, Double)?
    private var dists: [Double] = []         // last 40 deviations
    /// Largest deviation (g) inside the window that triggered the last motion event.
    private(set) var lastPeak = 0.0
    /// Which rule fired last: "strong" or "weak".
    private(set) var lastRule = ""

    init(sensitivity: MotionSensitivity) { threshold = sensitivity.threshold }

    var isCalibrated: Bool { baseline != nil }
    var reference: (Double, Double, Double)? { baseline }

    mutating func reset() { samples = []; baseline = nil; dists = [] }

    /// Sliding window: the newest `calibrationCount` samples. As soon as they are all still, they become the
    /// reference. Movement never restarts the count, so the sensor is ready right after the Mac stops being touched.
    mutating func feed(x: Double, y: Double, z: Double) -> Event {
        guard var b = baseline else {
            samples.append((x, y, z))
            if samples.count > Self.calibrationCount { samples.removeFirst(samples.count - Self.calibrationCount) }
            if samples.count >= Self.calibrationCount, let m = stillMean(of: samples) {
                baseline = m; samples = []
                return .calibrated
            }
            return .none
        }
        let d = Self.dist((x, y, z), b)
        dists.append(d)
        if dists.count > Self.weakWindowSize { dists.removeFirst() }

        let strong = strongThreshold
        let lastTen = dists.suffix(Self.windowSize)
        if lastTen.filter({ $0 > strong }).count >= Self.requiredOver {
            lastPeak = lastTen.max() ?? d; lastRule = "strong"; dists.removeAll()
            return .motion
        }
        if threshold < strong, dists.count >= Self.weakWindowSize,
           dists.filter({ $0 > threshold }).count >= Self.weakRequired {
            lastPeak = dists.max() ?? d; lastRule = "weak"; dists.removeAll()
            return .motion
        }
        if d < threshold {                        // quiet: follow very slow drift
            b.0 += (x - b.0) * Self.adapt; b.1 += (y - b.1) * Self.adapt; b.2 += (z - b.2) * Self.adapt
            baseline = b
        }
        return .none
    }

    /// Mean of the samples if they are all within half the threshold of it (the Mac is still), otherwise nil.
    private func stillMean(of window: [(Double, Double, Double)]) -> (Double, Double, Double)? {
        let n = Double(window.count)
        guard n > 0 else { return nil }
        let m = (window.map { $0.0 }.reduce(0, +) / n,
                 window.map { $0.1 }.reduce(0, +) / n,
                 window.map { $0.2 }.reduce(0, +) / n)
        let worst = window.map { Self.dist($0, m) }.max() ?? 0
        return worst > threshold * 0.5 ? nil : m
    }

    /// Called when the screen locks and the sensor is not calibrated yet: if the last ~0.4 s were still,
    /// use them as the reference now, so a movement right after the lock is not missed.
    mutating func calibrateNow() -> Bool {
        guard baseline == nil, samples.count >= Self.quickCalibrationCount,
              let m = stillMean(of: Array(samples.suffix(Self.quickCalibrationCount))) else { return false }
        baseline = m; samples = []
        return true
    }

    private static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dx = a.0 - b.0, dy = a.1 - b.1, dz = a.2 - b.2
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
