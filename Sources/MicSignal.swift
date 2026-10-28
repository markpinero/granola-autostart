import CoreAudio
import Foundation

/// Active while an allowed call app is capturing from any input device.
final class MicSignal: Signal {
    static let defaultAllowed: Set<String> = [
        "us.zoom.", "com.google.Chrome", "com.microsoft.teams",
        "com.tinyspeck.slackmacgap", "com.apple.FaceTime",
    ]
    let name = "mic"
    let allowed: Set<String>
    init(allowed: Set<String> = MicSignal.defaultAllowed) { self.allowed = allowed }

    static func matches(bundleID: String, allowed: Set<String>) -> Bool {
        allowed.contains { bundleID.hasPrefix($0) }
    }

    func isActive(now: Date) -> Bool {
        Self.inputBundleIDs().contains { Self.matches(bundleID: $0, allowed: allowed) }
    }

    static func inputBundleIDs() -> [String] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 else { return nil }
            var bundle: Unmanaged<CFString>?
            var bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var baddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &baddr, 0, nil, &bsize, &bundle) == noErr,
                  let b = bundle?.takeRetainedValue() else { return nil }
            return b as String
        }
    }
}
