import Foundation

/// Fake beat for the equalizer: needs no audio permission and shows no recording indicator.
@MainActor
final class SimulatedSpectrum {
  private let onLevels: ([Float]) -> Void
  private var timer: Timer?
  private var time: Float = 0

  init(onLevels: @escaping ([Float]) -> Void) {
    self.onLevels = onLevels
  }

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  // Two slow waves for the body, random spikes for texture, and a kick drum in the low bands.
  private func tick() {
    time += 1.0 / 40
    let count = AudioSpectrum.bandCount
    let kick = pow(max(0, sin(time * 7.3)), 6)
    onLevels((0..<count).map { band in
      // Patterns were tuned on 96 bands; scaling keeps their shape at any band count.
      let x = Float(band) * 96 / Float(count)
      let body = 0.15 + 0.4 * abs(sin(x * 0.53 + time * 2.3)) * abs(cos(x * 0.17 - time * 1.1))
      let spike: Float = Float.random(in: 0..<1) < 0.12 ? .random(in: 0..<0.5) : 0
      let drum = kick * 0.5 * exp(-pow(x - 96 * 0.3, 2) / 300)
      return min(body + spike + drum, 1)
    })
  }
}
