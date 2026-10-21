import AudioToolbox
import CoreAudio
import Foundation

/// Intercepts the audio of a group of processes, mutes the original stream and
/// plays it back through the output device with a custom gain.
final class ProcessTap {
    let processObjectIDs: [AudioObjectID]
    let outputDeviceUID: String

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let gainPointer: UnsafeMutablePointer<Float>
    private let queue = DispatchQueue(label: "SoundControl.ProcessTap", qos: .userInteractive)

    var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = max(0, newValue) }
    }

    init(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        gainPointer = .allocate(capacity: 1)
        gainPointer.initialize(to: gain)

        do {
            try start()
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
        gainPointer.deallocate()
    }

    private func start() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "SoundControl"

        try check(AudioHardwareCreateProcessTap(description, &tapID), "Crear tap de audio")

        let tapFormat = try tapID.read(
            tapID.address(kAudioTapPropertyFormat),
            initial: AudioStreamBasicDescription()
        )
        let tapChannels = max(Int(tapFormat.mChannelsPerFrame), 1)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundControl",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString
                ]
            ]
        ]

        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
            "Crear dispositivo agregado"
        )

        let gainPointer = gainPointer
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, inputData, _, outputData, _ in
            ProcessTap.render(
                input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData)),
                output: UnsafeMutableAudioBufferListPointer(outputData),
                tapChannels: tapChannels,
                gain: gainPointer.pointee
            )
        }, "Crear IOProc")

        try check(AudioDeviceStart(aggregateID, ioProcID), "Iniciar dispositivo")
    }

    /// Copies the tapped channels (the last input channels of the aggregate device)
    /// into every output buffer, applying the gain. Runs on the real-time audio thread.
    private static func render(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        tapChannels: Int,
        gain: Float
    ) {
        var inputChannels = 0
        for buffer in input { inputChannels += Int(buffer.mNumberChannels) }
        let tapStart = max(inputChannels - tapChannels, 0)
        let availableTapChannels = inputChannels - tapStart

        var outputChannelBase = 0
        for buffer in output {
            guard let outData = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outChannels = max(Int(buffer.mNumberChannels), 1)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)

            guard availableTapChannels > 0 else {
                memset(outData, 0, Int(buffer.mDataByteSize))
                outputChannelBase += outChannels
                continue
            }

            for channel in 0..<outChannels {
                // Locate the source channel inside the input buffer list.
                var remaining = tapStart + (outputChannelBase + channel) % availableTapChannels
                var source: UnsafeMutablePointer<Float>?
                var sourceStride = 1
                var sourceFrames = 0
                for inBuffer in input {
                    let count = Int(inBuffer.mNumberChannels)
                    if remaining < count {
                        source = inBuffer.mData?.assumingMemoryBound(to: Float.self).advanced(by: remaining)
                        sourceStride = max(count, 1)
                        sourceFrames = Int(inBuffer.mDataByteSize) / (MemoryLayout<Float>.size * sourceStride)
                        break
                    }
                    remaining -= count
                }

                for frame in 0..<frames {
                    if let source, frame < sourceFrames {
                        outData[frame * outChannels + channel] = source[frame * sourceStride] * gain
                    } else {
                        outData[frame * outChannels + channel] = 0
                    }
                }
            }
            outputChannelBase += outChannels
        }
    }

    func invalidate() {
        if aggregateID.isValid, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }
}
