// Prints BlackHole's volume; with "set" argument, forces it to 1.0 (it installs at ~0.2).
import CoreAudio

var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
let set = CommandLine.arguments.count > 1

for id in ids {
    var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var s = UInt32(MemoryLayout<CFString?>.size)
    AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &s, &name)
    guard let n = name?.takeRetainedValue() as String?, n.contains("BlackHole") else { continue }
    for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeInput] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: 0)
        guard AudioObjectHasProperty(id, &a) else { continue }
        if set {
            var one: Float32 = 1
            AudioObjectSetPropertyData(id, &a, 0, nil, 4, &one)
        }
        var v: Float32 = 0
        var vs = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &vs, &v)
        print(n, scope == kAudioObjectPropertyScopeOutput ? "out" : "in", v)
    }
}
