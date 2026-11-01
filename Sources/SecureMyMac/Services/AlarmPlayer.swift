import Foundation
import AVFoundation
import AppKit

@MainActor
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    private var fallbackTimer: Timer?
    private var testStop: Task<Void, Never>?
    static let maxVolume: Float = 0.8   // app volume cap; system volume is not touched
    private(set) var isPlaying = false
    private var warm = false
    var usedFallback = false
    /// Tests set this so no real sound is played.
    var muted = false

    /// Starts the siren silently (volume 0) so the audio device is already running.
    /// The real alarm then only raises the volume, with no 1-2 second start-up delay.
    func prewarm() {
        guard !muted, !isPlaying, !warm else { return }
        guard let url = AppResources.url("alert", ext: "wav"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        player = p
        warm = true
    }

    func play(loop: Bool = true) {
        if warm, let p = player, !muted {
            warm = false
            isPlaying = true
            usedFallback = false
            p.currentTime = 0
            p.volume = Self.maxVolume
            return
        }
        stop()
        isPlaying = true
        usedFallback = false
        if muted { return }
        if let url = AppResources.url("alert", ext: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = loop ? -1 : 0
            p.volume = Self.maxVolume
            p.prepareToPlay()
            p.play()
            player = p
        } else {
            usedFallback = true
            NSSound.beep()
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in NSSound.beep() }
        }
    }

    /// Plays for a few seconds, then stops itself.
    func playTest(seconds: Double = 4, onFinish: @escaping @MainActor () -> Void) {
        play(loop: true)
        testStop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
            onFinish()
        }
    }

    func stop() {
        warm = false
        testStop?.cancel(); testStop = nil
        player?.stop(); player = nil
        fallbackTimer?.invalidate(); fallbackTimer = nil
        isPlaying = false
    }
}
