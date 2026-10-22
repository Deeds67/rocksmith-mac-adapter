import CoreAudio
import Foundation
import os

let args = CommandLine.arguments
let inQuery = args.count > 1 ? args[1] : "Scarlett"
let chIdx = max(1, args.count > 2 ? Int(args[2]) ?? 1 : 1) - 1
let outName = "Rocksmith USB Guitar Adapter"

func devices() -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var sz: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz)
    var ids = [AudioObjectID](repeating: 0, count: Int(sz) / 4)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &ids)
    return ids
}
func name(_ d: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var s: Unmanaged<CFString>?
    var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(d, &a, 0, nil, &sz, &s)
    return (s?.takeRetainedValue() as String?) ?? ""
}
func find(_ n: String) -> AudioObjectID? { devices().first { name($0) == n } }
// Input: exact name first, else first device whose name contains the query (case-insensitive).
func findInput(_ q: String) -> AudioObjectID? {
    find(q) ?? devices().first { name($0) != outName && name($0).localizedCaseInsensitiveContains(q) }
}

guard let inDev = findInput(inQuery) else {
    FileHandle.standardError.write("ERROR: no input device matching '\(inQuery)'. Pass part of your interface's name as the first argument. Available: \(devices().map(name))\n".data(using: .utf8)!); exit(1)
}
guard let outDev = find(outName) else {
    FileHandle.standardError.write("ERROR: virtual device '\(outName)' not found (driver installed? coreaudiod restarted?). Available: \(devices().map(name))\n".data(using: .utf8)!); exit(1)
}
let inName = name(inDev)
print("input: \(inName) (id \(inDev)) channel \(chIdx + 1); output: \(outName) (id \(outDev))")

func setProp<T>(_ d: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ v: T) {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var v = v
    let r = AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    if r != 0 { print("warn: set \(sel) failed \(r)") }
}
setProp(inDev, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(48000))
setProp(outDev, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(48000))
setProp(inDev, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, UInt32(64))
setProp(outDev, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, UInt32(64))

// Ring buffer (mono float), guarded by unfair lock.
let cap = 4096
var ring = [Float](repeating: 0, count: cap)
var rd = 0, wr = 0 // monotonically increasing
var primed = false
let lock = OSAllocatedUnfairLock()

var inInterleavedCh = 1
func push(_ x: Float) {
    ring[wr % cap] = x; wr += 1
    if wr - rd > cap { rd = wr - cap } // overrun: drop oldest
}

let inQ = DispatchQueue(label: "in", qos: .userInteractive)
let outQ = DispatchQueue(label: "out", qos: .userInteractive)
var inProc: AudioDeviceIOProcID?
var outProc: AudioDeviceIOProcID?

var st = AudioDeviceCreateIOProcIDWithBlock(&inProc, inDev, inQ) { _, inData, _, _, _ in
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard abl.count > 0 else { return }
    lock.lock(); defer { lock.unlock() }
    if abl.count > 1 || Int(abl[0].mNumberChannels) == 1 {
        // non-interleaved: one buffer per channel
        let b = abl.count > chIdx ? abl[chIdx] : abl[0]
        guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { return }
        for i in 0..<Int(b.mDataByteSize) / 4 { push(p[i]) }
    } else {
        let b = abl[0]
        let n = Int(b.mNumberChannels)
        guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { return }
        let c = min(chIdx, n - 1)
        for f in 0..<Int(b.mDataByteSize) / 4 / n { push(p[f * n + c]) }
    }
}
guard st == 0 else { print("ERROR: input IOProc \(st)"); exit(1) }

st = AudioDeviceCreateIOProcIDWithBlock(&outProc, outDev, outQ) { _, _, _, outData, _ in
    let abl = UnsafeMutableAudioBufferListPointer(outData)
    guard abl.count > 0 else { return }
    lock.lock(); defer { lock.unlock() }
    let b0 = abl[0]
    let n = abl.count > 1 ? 1 : Int(b0.mNumberChannels)
    let frames = Int(b0.mDataByteSize) / 4 / max(n, 1)
    if !primed {
        if wr - rd >= frames { primed = true } // prefill ~1 buffer
    }
    if primed && wr - rd < frames { primed = false } // underrun -> zeros until refilled
    // Latency cap: never let more than ~2 blocks pile up (clock drift / startup backlog).
    if wr - rd > frames * 2 { rd = wr - frames }
    for f in 0..<frames {
        let s: Float = primed ? { let v = ring[rd % cap]; rd += 1; return v }() : 0
        for (bi, b) in abl.enumerated() {
            guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let nc = Int(b.mNumberChannels)
            for c in 0..<nc { p[f * nc + c] = s }
            _ = bi
        }
    }
}
guard st == 0 else { print("ERROR: output IOProc \(st)"); exit(1) }

AudioDeviceStart(inDev, inProc)
AudioDeviceStart(outDev, outProc)
print("running; Ctrl-C to stop")
signal(SIGINT) { _ in exit(0) }
dispatchMain()
