import AppKit

/// Song and time above an equalizer strip that doubles as the progress bar.
/// Sliding a finger across the view scrubs; lifting it seeks.
final class TrackView: NSView {
  var track: NowPlaying? { didSet { needsDisplay = true } }
  var hint: String? { didSet { needsDisplay = true } }
  var onSeek: ((Double) -> Void)?
  var style = SpectrumStyle.needles { didSet { needsDisplay = true } }
  private var scrubFraction: Double?
  private var bars = [Float](repeating: 0, count: AudioSpectrum.bandCount)
  private var peaks = [Float](repeating: 0, count: AudioSpectrum.bandCount)

  override init(frame: NSRect) {
    super.init(frame: frame)
    allowedTouchTypes = [.direct]
  }

  required init?(coder: NSCoder) { fatalError("TrackView is built in code") }

  override var intrinsicContentSize: NSSize { NSSize(width: 380, height: 30) }

  // Bars jump up at once and fall back gently; peak dots hang a little longer.
  func show(levels: [Float]) {
    for i in bars.indices {
      bars[i] = max(levels[i], bars[i] * 0.8)
      peaks[i] = max(bars[i], peaks[i] - 0.012)
    }
    needsDisplay = true
  }

  func clearLevels() {
    guard bars.contains(where: { $0 > 0 }) || peaks.contains(where: { $0 > 0 }) else { return }
    bars = bars.map { _ in 0 }
    peaks = bars
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let secondary: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    guard let track else {
      hint?.draw(at: NSPoint(x: 0, y: 9), withAttributes: secondary)
      return
    }
    let fraction = scrubFraction ?? (track.duration > 0 ? track.position / track.duration : 0)
    let position = scrubFraction.map { $0 * track.duration } ?? track.position

    let time = "\(clock(position)) / \(clock(track.duration))"
    let timeWidth = time.size(withAttributes: secondary).width
    time.draw(
      at: NSPoint(x: bounds.width - timeWidth, y: stripHeight + 0.5), withAttributes: secondary)

    let truncating = NSMutableParagraphStyle()
    truncating.lineBreakMode = .byTruncatingTail
    "\(track.title) — \(track.artist)".draw(
      with: NSRect(x: 0, y: stripHeight, width: bounds.width - timeWidth - 8, height: 13),
      options: .usesLineFragmentOrigin,
      attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: truncating,
      ])

    drawSpectrum(playedUntil: bounds.width * fraction)
  }

  private func drawSpectrum(playedUntil: CGFloat) {
    style.draw(SpectrumFrame(
      rect: NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight), bars: bars, peaks: peaks,
      playedUntil: playedUntil))
    guard style.drawsPlayhead else { return }
    NSColor.white.setFill()
    NSRect(x: min(playedUntil, bounds.width - 1.5), y: 0, width: 1.5, height: stripHeight).fill()
  }

  override func touchesBegan(with event: NSEvent) { scrub(event) }
  override func touchesMoved(with event: NSEvent) { scrub(event) }

  override func touchesEnded(with event: NSEvent) {
    scrub(event)
    if let scrubFraction, let duration = track?.duration { onSeek?(scrubFraction * duration) }
    scrubFraction = nil
  }

  override func touchesCancelled(with event: NSEvent) {
    scrubFraction = nil
    needsDisplay = true
  }

  private func scrub(_ event: NSEvent) {
    guard (track?.duration ?? 0) > 0,
          let x = event.touches(matching: .any, in: self).first?.location(in: self).x
    else { return }
    scrubFraction = min(max(Double(x / bounds.width), 0), 1)
    needsDisplay = true
  }
}

/// The equalizer gets the 17 pt under the 10 pt title line, of the bar's 30 pt.
private let stripHeight: CGFloat = 17

private func clock(_ seconds: Double) -> String {
  let total = Int(seconds)
  return total >= 3600
    ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    : String(format: "%d:%02d", total / 60, total % 60)
}
