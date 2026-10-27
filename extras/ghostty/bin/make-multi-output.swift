// Creates a persistent Multi-Output Device: MacBook speakers (clock source) + BlackHole.
// Usage: swift make-multi-output.swift <speakers-uid> <blackhole-uid>
import CoreAudio
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: make-multi-output <speakers-uid> <blackhole-uid>") }
let (speakers, blackhole) = (args[1], args[2])

let desc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "Speakers + BlackHole",
    kAudioAggregateDeviceUIDKey: "ghostty-audio-multi-output",
    kAudioAggregateDeviceIsStackedKey: 1,
    kAudioAggregateDeviceIsPrivateKey: 0,
    kAudioAggregateDeviceMainSubDeviceKey: speakers,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: speakers],
        [kAudioSubDeviceUIDKey: blackhole, kAudioSubDeviceDriftCompensationKey: 1],
    ],
]

var id = AudioObjectID(0)
let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
guard status == noErr else { fatalError("AudioHardwareCreateAggregateDevice failed: \(status)") }
print("created device id \(id)")
