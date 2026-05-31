import CoreAudio
import Foundation
import FootswitchCore

/// Toggles hardware mute on the system default audio input device via the
/// CoreAudio HAL. The default input is resolved live on each toggle so it follows
/// whatever microphone is currently selected (built-in, USB, AirPods, …).
final class AudioInputMuter: InputMuting {
    func toggleInputMute() {
        guard let device = defaultInputDevice() else { return }

        // Mute lives on the input scope (kAudioObjectPropertyScopeInput). Some
        // devices expose it per-channel (element 1..n) rather than on the master
        // element (0); try master first, then fall back to channel 1.
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }

            var current: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let getStatus = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &current)
            guard getStatus == noErr else { continue }

            var toggled: UInt32 = current == 0 ? 1 : 0
            let setStatus = AudioObjectSetPropertyData(
                device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &toggled)
            if setStatus == noErr { return }
        }
    }

    private func defaultInputDevice() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }
}
