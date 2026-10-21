import CoreAudio
import Foundation

/// Reads and writes the volume and mute state of the default output device.
@MainActor
final class SystemVolumeController: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var deviceName = ""
    @Published private(set) var canChangeVolume = false

    private var deviceID = AudioObjectID.unknown
    private var defaultDeviceListener: PropertyListener?
    private var deviceListeners: [PropertyListener] = []

    init() {
        let system = AudioObjectID.system
        defaultDeviceListener = PropertyListener(
            objectID: system,
            address: system.address(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in
            Task { @MainActor in self?.attachToDefaultDevice() }
        }
        attachToDefaultDevice()
    }

    func setVolume(_ newValue: Float) {
        let value = min(max(newValue, 0), 1)
        for element in volumeElements() {
            try? deviceID.write(
                deviceID.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element),
                value: Float32(value)
            )
        }
        if isMuted && value > 0 { setMuted(false) }
        volume = value
    }

    func toggleMute() { setMuted(!isMuted) }

    private func setMuted(_ muted: Bool) {
        let address = deviceID.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard deviceID.isSettable(address) else { return }
        try? deviceID.write(address, value: UInt32(muted ? 1 : 0))
        isMuted = muted
    }

    private func attachToDefaultDevice() {
        deviceID = AudioObjectID.defaultOutputDevice()
        deviceName = deviceID.readString(deviceID.address(kAudioObjectPropertyName)) ?? ""
        canChangeVolume = !volumeElements().isEmpty

        var addresses = [deviceID.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)]
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            addresses.append(deviceID.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element))
        }
        deviceListeners = addresses
            .filter { deviceID.hasProperty($0) }
            .compactMap { address in
                PropertyListener(objectID: deviceID, address: address) { [weak self] in
                    Task { @MainActor in self?.readState() }
                }
            }
        readState()
    }

    private func readState() {
        let elements = volumeElements()
        let values = elements.compactMap {
            try? deviceID.read(
                deviceID.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: $0),
                initial: Float32(0)
            )
        }
        volume = values.max() ?? 0

        let muteAddress = deviceID.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        isMuted = ((try? deviceID.read(muteAddress, initial: UInt32(0))) ?? 0) != 0
    }

    /// Uses the main element when the device exposes it, otherwise the left/right channels.
    private func volumeElements() -> [AudioObjectPropertyElement] {
        let main = deviceID.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
        if deviceID.isSettable(main) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter {
            deviceID.isSettable(deviceID.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: $0))
        }
    }
}
