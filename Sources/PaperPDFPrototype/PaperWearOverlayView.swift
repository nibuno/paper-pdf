import AppKit
import PaperPDFCore

@MainActor
final class PaperWearOverlayView: NSView {
  let pageIndex: Int

  private var visitCount: Int
  private var textureSeed: UInt64

  init(pageIndex: Int, visitCount: Int, textureSeed: UInt64) {
    self.pageIndex = pageIndex
    self.visitCount = visitCount
    self.textureSeed = textureSeed
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    updatePageShadow()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // The paper layer is visual only. Selection, drawing, and page navigation
    // must continue to reach PDFView underneath it.
    nil
  }

  func update(visitCount: Int, textureSeed: UInt64) {
    guard self.visitCount != visitCount || self.textureSeed != textureSeed else { return }
    self.visitCount = visitCount
    self.textureSeed = textureSeed
    updatePageShadow()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    updatePageShadow()
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext,
      bounds.width > 0,
      bounds.height > 0
    else { return }

    let paperBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
    let profile = PageWearProfile(visitCount: visitCount)
    guard profile.stage > 0 else { return }

    context.saveGState()
    drawPaperTone(in: context, bounds: paperBounds, profile: profile)
    drawPaperTexture(in: context, bounds: paperBounds, profile: profile)
    drawEdgeDullness(in: context, bounds: paperBounds, profile: profile)
    context.restoreGState()
  }

  static func stableSeed(fingerprint: String, pageIndex: Int) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in "\(fingerprint)#\(pageIndex)".utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return hash
  }

  private func updatePageShadow() {
    guard let layer else { return }
    let profile = PageWearProfile(visitCount: visitCount)
    layer.shadowColor = NSColor.black.cgColor
    layer.shadowOpacity = Float(profile.shadowOpacity)
    layer.shadowRadius = 3 + CGFloat(profile.stage) * 1.4
    layer.shadowOffset = CGSize(width: 0, height: -1 - CGFloat(profile.stage) * 0.6)
    layer.shadowPath = bounds.isEmpty
      ? nil
      : CGPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
  }

  private func drawPaperTone(
    in context: CGContext,
    bounds: CGRect,
    profile: PageWearProfile
  ) {
    // Warm the sheet as a whole instead of placing recognisable stains on it.
    // This remains visible when a complete page is fitted to the window.
    context.setBlendMode(.multiply)
    context.setFillColor(
      NSColor(
        calibratedRed: 0.72,
        green: 0.66,
        blue: 0.54,
        alpha: CGFloat(profile.paperToneAlpha)
      ).cgColor
    )
    context.fill(bounds)
  }

  private func drawPaperTexture(
    in context: CGContext,
    bounds: CGRect,
    profile: PageWearProfile
  ) {
    var generator = PaperTextureGenerator(seed: textureSeed)
    let shortestSide = min(bounds.width, bounds.height)
    context.setBlendMode(.multiply)
    context.setLineCap(.round)

    // A sparse layer of longer pulp fibres survives fit-to-page scaling without
    // turning into speckles or scratch-like marks.
    context.setStrokeColor(
      NSColor(
        calibratedRed: 0.48,
        green: 0.44,
        blue: 0.36,
        alpha: CGFloat(profile.textureAlpha) * 0.55
      ).cgColor
    )
    for _ in 0..<180 {
      let x = bounds.minX + generator.unit() * bounds.width
      let y = bounds.minY + generator.unit() * bounds.height
      let length = shortestSide * (0.008 + generator.unit() * 0.024)
      let drift = shortestSide * (generator.unit() - 0.5) * 0.006
      context.setLineWidth(max(0.32, shortestSide * (0.00028 + generator.unit() * 0.00024)))
      context.beginPath()
      context.move(to: CGPoint(x: x, y: y))
      context.addLine(to: CGPoint(x: min(x + length, bounds.maxX), y: y + drift))
      context.strokePath()
    }

    // The denser short fibres provide the actual paper grain. Their direction
    // drifts slightly so the page does not read as a repeated screen texture.
    context.setStrokeColor(
      NSColor(
        calibratedRed: 0.43,
        green: 0.41,
        blue: 0.36,
        alpha: CGFloat(profile.textureAlpha)
      ).cgColor
    )
    for _ in 0..<1_100 {
      let x = bounds.minX + generator.unit() * bounds.width
      let y = bounds.minY + generator.unit() * bounds.height
      let length = shortestSide * (0.0018 + generator.unit() * 0.0082)
      let drift = shortestSide * (generator.unit() - 0.5) * 0.0035
      context.setLineWidth(max(0.28, shortestSide * (0.00022 + generator.unit() * 0.00020)))
      context.beginPath()
      context.move(to: CGPoint(x: x, y: y))
      context.addLine(to: CGPoint(x: min(x + length, bounds.maxX), y: y + drift))
      context.strokePath()
    }
  }

  private func drawEdgeDullness(
    in context: CGContext,
    bounds: CGRect,
    profile: PageWearProfile
  ) {
    var generator = PaperTextureGenerator(seed: textureSeed ^ 0xA24B_AED4_963E_E407)
    let shortestSide = min(bounds.width, bounds.height)
    let bandDepth = shortestSide * CGFloat(profile.edgeDepthFraction)
    let baseAlpha = CGFloat(profile.edgeDullnessAlpha)
    let outerEdge: PaperEdge = pageIndex.isMultiple(of: 2) ? .right : .left

    drawEdgeBand(
      outerEdge,
      in: context,
      bounds: bounds,
      depth: bandDepth,
      alpha: baseAlpha,
      generator: &generator
    )
    drawEdgeBand(
      outerEdge.opposite,
      in: context,
      bounds: bounds,
      depth: bandDepth * 0.82,
      alpha: baseAlpha * 0.68,
      generator: &generator
    )
    drawEdgeBand(
      .bottom,
      in: context,
      bounds: bounds,
      depth: bandDepth * 0.88,
      alpha: baseAlpha * 0.76,
      generator: &generator
    )
    drawEdgeBand(
      .top,
      in: context,
      bounds: bounds,
      depth: bandDepth * 0.72,
      alpha: baseAlpha * 0.54,
      generator: &generator
    )
  }

  private func drawEdgeBand(
    _ edge: PaperEdge,
    in context: CGContext,
    bounds: CGRect,
    depth: CGFloat,
    alpha: CGFloat,
    generator: inout PaperTextureGenerator
  ) {
    guard depth > 0, alpha > 0 else { return }

    let segmentCount = 22
    var innerBoundary: [CGPoint] = []
    for index in 0...segmentCount {
      let progress = CGFloat(index) / CGFloat(segmentCount)
      let variedDepth = depth * (0.72 + generator.unit() * 0.28)
      let point = switch edge {
      case .left:
        CGPoint(x: bounds.minX + variedDepth, y: bounds.minY + bounds.height * progress)
      case .right:
        CGPoint(x: bounds.maxX - variedDepth, y: bounds.minY + bounds.height * progress)
      case .top:
        CGPoint(x: bounds.minX + bounds.width * progress, y: bounds.maxY - variedDepth)
      case .bottom:
        CGPoint(x: bounds.minX + bounds.width * progress, y: bounds.minY + variedDepth)
      }
      innerBoundary.append(point)
    }

    let path = CGMutablePath()
    switch edge {
    case .left:
      path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
      path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY))
    case .right:
      path.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
      path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
    case .top:
      path.move(to: CGPoint(x: bounds.minX, y: bounds.maxY))
      path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
    case .bottom:
      path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
      path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
    }
    for point in innerBoundary.reversed() {
      path.addLine(to: point)
    }
    path.closeSubpath()

    let outerColor = NSColor(
      calibratedRed: 0.46,
      green: 0.45,
      blue: 0.42,
      alpha: alpha
    ).cgColor
    let middleColor = NSColor(
      calibratedRed: 0.50,
      green: 0.49,
      blue: 0.46,
      alpha: alpha * 0.32
    ).cgColor
    let clearColor = NSColor(
      calibratedRed: 0.50,
      green: 0.49,
      blue: 0.46,
      alpha: 0
    ).cgColor
    guard let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [outerColor, middleColor, clearColor] as CFArray,
      locations: [0, 0.58, 1]
    ) else { return }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let start: CGPoint
    let end: CGPoint
    switch edge {
    case .left:
      start = CGPoint(x: bounds.minX, y: center.y)
      end = CGPoint(x: bounds.minX + depth, y: center.y)
    case .right:
      start = CGPoint(x: bounds.maxX, y: center.y)
      end = CGPoint(x: bounds.maxX - depth, y: center.y)
    case .top:
      start = CGPoint(x: center.x, y: bounds.maxY)
      end = CGPoint(x: center.x, y: bounds.maxY - depth)
    case .bottom:
      start = CGPoint(x: center.x, y: bounds.minY)
      end = CGPoint(x: center.x, y: bounds.minY + depth)
    }

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.setBlendMode(.multiply)
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
  }
}

private enum PaperEdge {
  case left
  case right
  case top
  case bottom

  var opposite: PaperEdge {
    switch self {
    case .left: .right
    case .right: .left
    case .top: .bottom
    case .bottom: .top
    }
  }
}

private struct PaperTextureGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func unit() -> CGFloat {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return CGFloat(Double(value >> 11) / 9_007_199_254_740_992)
  }
}
