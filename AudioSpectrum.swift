import Accelerate
import CoreAudio

/// Live spectrum of everything the Mac plays, read through a Core Audio process tap.
/// Needs the "System Audio Recording" permission; without it the tap delivers silence.
// @unchecked: `samples` is touched only on `queue`; start and stop run on the main thread.
final class AudioSpectrum: @unchecked Sendable {
  static let bandCount = 96
  private static let size = 2048

  private let onLevels: @Sendable ([Float]) -> Void
  private let queue = DispatchQueue(label: "local.touchbar-display.audio")
  private let dft = try! vDSP.DiscreteFourierTransform(
    count: size, direction: .forward, transformType: .complexComplex, ofType: Float.self)
  private let window = vDSP.window(
    ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
  private let silence = [Float](repeating: 0, count: size)
  private var samples: [Float] = []
  private var bandEdges: [Int] = []
  private var reference: Float = -70
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var deviceID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?

  init(onLevels: @escaping @Sendable ([Float]) -> Void) {
    self.onLevels = onLevels
  }

  func start() {
    guard procID == nil else { return }
    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    description.isPrivate = true
    description.muteBehavior = .unmuted
    guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
          let outputUID = defaultOutputUID()
    else { return stop() }
    bandEdges = Self.logBandEdges(sampleRate: tapSampleRate())

    let settings: [String: Any] = [
      kAudioAggregateDeviceNameKey: "TouchBarDisplay Tap",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
      ],
    ]
    guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &deviceID) == noErr,
          AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue, { [weak self] _, input, _, _, _ in
            self?.consume(input)
          }) == noErr,
          AudioDeviceStart(deviceID, procID) == noErr
    else { return stop() }
  }

  func stop() {
    if let procID {
      AudioDeviceStop(deviceID, procID)
      AudioDeviceDestroyIOProcID(deviceID, procID)
    }
    procID = nil
    if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    deviceID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
  }

  // Half-overlapping windows give a new frame about every 21 ms at 48 kHz.
  private func consume(_ input: UnsafePointer<AudioBufferList>) {
    guard let buffer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
          let data = buffer.mData
    else { return }
    let channels = Int(max(buffer.mNumberChannels, 1))
    let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
    let floats = data.assumingMemoryBound(to: Float.self)
    for frame in 0..<frames { samples.append(floats[frame * channels]) }
    guard samples.count >= Self.size else { return }
    let chunk = Array(samples.suffix(Self.size))
    samples.removeFirst(samples.count - Self.size / 2)
    onLevels(levels(of: chunk))
  }

  private func levels(of chunk: [Float]) -> [Float] {
    var real = silence
    var imaginary = silence
    dft.transform(
      inputReal: vDSP.multiply(chunk, window), inputImaginary: silence,
      outputReal: &real, outputImaginary: &imaginary)
    let half = Self.size / 2
    let magnitudes = vDSP.hypot(real[0..<half], imaginary[0..<half])
    let decibels = (0..<Self.bandCount).map { band in
      let peak = magnitudes[bandEdges[band]..<bandEdges[band + 1]].max() ?? 0
      // A Hann-windowed full-scale sine peaks at size / 4. Music loses energy as pitch rises,
      // so higher bands get up to 12 dB extra to keep the right side of the bar alive.
      return 20 * log10(max(peak / Float(Self.size / 4), 1e-6))
        + 12 * Float(band) / Float(Self.bandCount)
    }
    // Auto-gain: the loudest recent band tops the scale, so quiet volume still fills the needles.
    // The reference falls about 3 dB a second, and never below -70 dB so silence stays flat.
    reference = max(decibels.max() ?? -70, reference - 0.07, -70)
    return decibels.map { min(max(($0 - reference + 36) / 36, 0), 1) }
  }

  // Log-spaced 40 Hz to 16 kHz, each band at least one FFT bin wide.
  private static func logBandEdges(sampleRate: Double) -> [Int] {
    let binHz = sampleRate / Double(size)
    var edges: [Int] = []
    for band in 0...bandCount {
      let hz = 40 * pow(16_000 / 40, Double(band) / Double(bandCount))
      let bin = min(max(Int(hz / binHz), (edges.last ?? 0) + (band == 0 ? 0 : 1)), size / 2)
      edges.append(bin)
    }
    return edges
  }

  private func tapSampleRate() -> Double {
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
    return format.mSampleRate > 0 ? format.mSampleRate : 48_000
  }

  private func defaultOutputUID() -> String? {
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
    else { return nil }
    var uid: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    address.mSelector = kAudioDevicePropertyDeviceUID
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
    return uid?.takeRetainedValue() as String?
  }
}
