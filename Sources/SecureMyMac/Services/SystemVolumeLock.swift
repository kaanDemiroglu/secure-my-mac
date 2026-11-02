import Foundation
import CoreAudio

/// Alarm sırasında sistem sesini rahat duyulur bir seviyede tutar.
/// Ses 0'a çekilse ya da sessize alınsa bile kısa sürede geri düzeltir.
/// Alarm bitince önceki ses seviyesini geri yükler. Yetki (sudo) gerekmez.
@MainActor
final class SystemVolumeLock {
    /// Rahat duyulur ama çok yüksek olmayan seviye.
    static let targetVolume: Float32 = 0.85

    private var timer: Timer?
    private var saved: (device: AudioObjectID, volumes: [UInt32: Float32], mute: UInt32?)?

    var isLocked: Bool { timer != nil }

    func lock() {
        guard timer == nil else { return }
        if let device = Self.defaultOutputDevice() {
            var vols: [UInt32: Float32] = [:]
            for el in Self.volumeElements(device) { if let v = Self.getVolume(device, el) { vols[el] = v } }
            saved = (device, vols, Self.getMute(device))
        }
        enforce()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func unlock() {
        timer?.invalidate(); timer = nil
        guard let s = saved else { return }
        saved = nil
        for (el, v) in s.volumes { Self.setVolume(s.device, el, v) }
        if let m = s.mute { Self.setMute(s.device, m) }
    }

    private func enforce() {
        guard let device = Self.defaultOutputDevice() else { return }
        if Self.getMute(device) == 1 { Self.setMute(device, 0) }
        for el in Self.volumeElements(device) {
            if let v = Self.getVolume(device, el), v < Self.targetVolume - 0.01 || v > Self.targetVolume + 0.01 {
                Self.setVolume(device, el, Self.targetVolume)
            }
        }
    }

    // MARK: - CoreAudio yardımcıları

    private static func address(_ selector: AudioObjectPropertySelector, _ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (st == noErr && device != kAudioObjectUnknown) ? device : nil
    }

    /// Önce ana kanal (0); yoksa 1 ve 2. kanallar.
    private static func volumeElements(_ device: AudioObjectID) -> [UInt32] {
        var a = address(kAudioDevicePropertyVolumeScalar, 0)
        if AudioObjectHasProperty(device, &a) { return [0] }
        return [1, 2].filter { var b = address(kAudioDevicePropertyVolumeScalar, $0); return AudioObjectHasProperty(device, &b) }
    }

    private static func getVolume(_ device: AudioObjectID, _ el: UInt32) -> Float32? {
        var a = address(kAudioDevicePropertyVolumeScalar, el)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func setVolume(_ device: AudioObjectID, _ el: UInt32, _ value: Float32) {
        var a = address(kAudioDevicePropertyVolumeScalar, el)
        var v = value
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    private static func getMute(_ device: AudioObjectID) -> UInt32? {
        var a = address(kAudioDevicePropertyMute, 0)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &m) == noErr ? m : nil
    }

    private static func setMute(_ device: AudioObjectID, _ value: UInt32) {
        var a = address(kAudioDevicePropertyMute, 0)
        var m = value
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }
}
