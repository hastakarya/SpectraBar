import AppKit

/// Ways to draw the equalizer strip under the song title. Each style reads the same frame.
enum SpectrumStyle: String, CaseIterable {
  case needles, glowWaves, barsAndRibbons, reflection, centerPulse

  var title: String {
    switch self {
    case .needles: "Rainbow needles"
    case .glowWaves: "Glow waves"
    case .barsAndRibbons: "Bars and ribbons"
    case .reflection: "Reflection"
    case .centerPulse: "Center pulse"
    }
  }

  /// Center pulse marks progress with its own rings, so it skips the white playhead line.
  var drawsPlayhead: Bool { self != .centerPulse }

  func draw(_ frame: SpectrumFrame) {
    switch self {
    case .needles: drawNeedles(frame)
    case .glowWaves: drawGlowWaves(frame)
    case .barsAndRibbons: drawBarsAndRibbons(frame)
    case .reflection: drawReflection(frame)
    case .centerPulse: drawCenterPulse(frame)
    }
  }
}

/// Band levels, peak dots and song progress for one redraw of the strip.
struct SpectrumFrame {
  let rect: NSRect
  let bars: [Float]
  let peaks: [Float]
  let playedUntil: CGFloat
  /// Seconds, kept small so sine phases stay precise.
  let time = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)

  var mid: CGFloat { rect.midY }
  /// Styles were tuned on a 15 pt strip; this stretches them to the real height.
  var scale: CGFloat { rect.height / 15 }
  var step: CGFloat { rect.width / CGFloat(bars.count) }

  func x(of band: Int) -> CGFloat { rect.minX + CGFloat(band) * step }

  func level(at x: CGFloat) -> CGFloat {
    let band = Int((x - rect.minX) / rect.width * CGFloat(bars.count))
    return CGFloat(bars[min(max(band, 0), bars.count - 1)])
  }

  /// Played part bright, the rest dim.
  func alpha(at x: CGFloat) -> CGFloat { x < playedUntil ? 1 : 0.3 }

  /// Darkens the unplayed part for styles drawn as one gradient instead of per-band colors.
  func dimUnplayed() {
    NSColor(white: 0, alpha: 0.65).setFill()
    NSRect(x: playedUntil, y: rect.minY, width: rect.maxX - playedUntil, height: rect.height)
      .fill(using: .sourceOver)
  }
}

private func color(hue degrees: Double, saturation: CGFloat = 0.85, alpha: CGFloat = 1) -> NSColor {
  NSColor(
    hue: (degrees / 360).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: 1,
    alpha: alpha)
}

private func fill(_ rect: NSRect, _ color: NSColor) {
  color.setFill()
  rect.fill(using: .sourceOver)
}

private func drawNeedles(_ f: SpectrumFrame) {
  for band in f.bars.indices {
    let x = f.x(of: band)
    let tint = color(
      hue: Double(band) / Double(f.bars.count) * 300 + f.time * 40, alpha: f.alpha(at: x))
    let reach = f.rect.height - 5
    fill(NSRect(x: x, y: f.rect.minY + 1, width: 1, height: 1 + CGFloat(f.bars[band]) * reach), tint)
    fill(NSRect(x: x, y: f.rect.minY + 4 + CGFloat(f.peaks[band]) * reach, width: 1, height: 1), tint)
  }
}

// Three overlapping sine strokes whose height follows the spectrum, tinted cyan to magenta.
private func drawGlowWaves(_ f: SpectrumFrame) {
  guard let context = NSGraphicsContext.current?.cgContext else { return }
  let gradient = NSGradient(colors: [
    color(hue: 190), color(hue: 220), color(hue: 270), color(hue: 305),
  ])
  for layer in 0..<3 {
    let path = CGMutablePath()
    for x in stride(from: f.rect.minX, through: f.rect.maxX, by: 1) {
      let position = Double((x - f.rect.minX) / f.rect.width)
      let envelope = f.level(at: x) * 6.5 * f.scale * (0.6 + 0.4 * sin(position * .pi * 4 + Double(layer)))
      let y = f.mid + sin(Double(x) * (0.55 + Double(layer) * 0.07) - f.time * 6) * envelope
      x == f.rect.minX ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(1)
    context.replacePathWithStrokedPath()
    context.clip()
    context.setAlpha(0.45 + CGFloat(layer) * 0.25)
    gradient?.draw(in: f.rect, angle: 0)
    context.restoreGState()
  }
  f.dimUnplayed()
}

// Mirrored rainbow bars with thin white sine ribbons drifting across them.
private func drawBarsAndRibbons(_ f: SpectrumFrame) {
  for band in stride(from: 0, to: f.bars.count, by: 2) {
    let x = f.x(of: band)
    let half = CGFloat(f.bars[band]) * 6.5 * f.scale + 0.5
    fill(
      NSRect(x: x, y: f.mid - half, width: f.step * 1.3, height: half * 2),
      color(hue: 150 + Double(band) / Double(f.bars.count) * 220, alpha: f.alpha(at: x)))
  }
  NSColor(white: 1, alpha: 0.5).setStroke()
  for ribbon in 0..<4 {
    let path = NSBezierPath()
    path.lineWidth = 0.6
    for x in stride(from: f.rect.minX, through: f.rect.maxX, by: 2) {
      let y = f.mid + sin(Double(x) * 0.06 + f.time * 2 + Double(ribbon) * 0.5)
        * (2.5 + Double(ribbon) * 0.8) * f.scale
      x == f.rect.minX ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.stroke()
  }
}

// Bars stand on a floor line with a faint mirror below and a slow white curve on top.
private func drawReflection(_ f: SpectrumFrame) {
  let floor = f.rect.minY + 5 * f.scale
  for band in f.bars.indices {
    let x = f.x(of: band)
    let height = 1 + CGFloat(f.bars[band]) * 9 * f.scale
    let hue = 300 - Double(band) / Double(f.bars.count) * 120
    fill(NSRect(x: x, y: floor, width: f.step * 0.6, height: height),
         color(hue: hue, saturation: 0.7, alpha: f.alpha(at: x)))
    fill(NSRect(x: x, y: floor - 1 - height * 0.45, width: f.step * 0.6, height: height * 0.45),
         color(hue: hue, saturation: 0.7, alpha: f.alpha(at: x) * 0.3))
  }
  let curve = NSBezierPath()
  curve.lineWidth = 1
  for x in stride(from: f.rect.minX, through: f.rect.maxX, by: 2) {
    let y = floor + (4 + sin(Double(x) * 0.035 - f.time * 1.5) * 2) * f.scale
    x == f.rect.minX ? curve.move(to: NSPoint(x: x, y: y)) : curve.line(to: NSPoint(x: x, y: y))
  }
  NSColor(white: 1, alpha: 0.8).setStroke()
  curve.stroke()
}

// Needles shrink toward the playhead, blue behind it and magenta ahead; rings pulse with the bass.
private func drawCenterPulse(_ f: SpectrumFrame) {
  for band in f.bars.indices {
    let x = f.x(of: band)
    let gap = abs(x - f.playedUntil)
    guard gap > 7 else { continue }
    let distance = gap / f.rect.width
    let half = min(
      (0.5 + CGFloat(f.bars[band]) * 8) * (0.75 + distance * 0.5) * f.scale, f.rect.height / 2)
    fill(NSRect(x: x, y: f.mid - half, width: 1, height: half * 2),
         color(hue: x < f.playedUntil ? 205 : 315, alpha: 0.35 + 0.65 * (1 - distance)))
  }
  let bass = CGFloat(f.bars.prefix(8).reduce(0, +) / 8)
  for ring in 0..<3 {
    let growth = (f.time * 12 + Double(ring) * 6).truncatingRemainder(dividingBy: 18) + 2
    let radius = growth * 0.35 * f.scale
    color(hue: 275, saturation: 0.65, alpha: (1 - growth / 20) * (0.4 + bass * 0.6)).setStroke()
    let circle = NSBezierPath(ovalIn: NSRect(
      x: f.playedUntil - radius, y: f.mid - radius, width: radius * 2, height: radius * 2))
    circle.lineWidth = 1
    circle.stroke()
  }
  let dot = 1.8 + bass * 1.2
  color(hue: 275, saturation: 0.75).setFill()
  NSBezierPath(ovalIn: NSRect(
    x: f.playedUntil - dot, y: f.mid - dot, width: dot * 2, height: dot * 2)).fill()
}
