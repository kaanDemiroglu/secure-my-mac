import Foundation

/// Demo only. Tampering is triggered by a button, not by any sensor.
final class SimulationMotionProvider: MotionProvider {
    private var handler: (@MainActor () -> Void)?
    var availability: MotionAvailability { .available }
    var isSimulation: Bool { true }
    var sampleCount: Int { 1 }
    func start(onMotion: @escaping @MainActor () -> Void) { handler = onMotion }
    func stop() { handler = nil }
    @MainActor func simulate() { handler?() }
}
