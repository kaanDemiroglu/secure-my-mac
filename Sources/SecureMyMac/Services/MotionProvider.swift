import Foundation

enum MotionAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

protocol MotionProvider: AnyObject {
    var availability: MotionAvailability { get }
    var isSimulation: Bool { get }
    /// Number of real sensor samples received since start (0 means the sensor is silent).
    var sampleCount: Int { get }
    func start(onMotion: @escaping @MainActor () -> Void)
    func stop()
}
