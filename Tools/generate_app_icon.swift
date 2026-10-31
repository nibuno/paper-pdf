// アプリアイコンの元画像（1024px PNG）を描画する。
// 使い方: swift Tools/generate_app_icon.swift <出力先PNG>

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let side = 1024
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
  CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

guard let ctx = CGContext(
  data: nil,
  width: side,
  height: side,
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: space,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
  FileHandle.standardError.write(Data("描画コンテキストを作れませんでした\n".utf8))
  exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// 背景（角丸の下地とインク色のグラデーション）
let inset: CGFloat = 60
let plate = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let platePath = CGPath(roundedRect: plate, cornerWidth: 224, cornerHeight: 224, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: rgb(0, 0, 0, 0.35))
ctx.addPath(platePath)
ctx.setFillColor(rgb(40, 56, 92))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let backdrop = CGGradient(
  colorsSpace: space,
  colors: [rgb(92, 124, 178), rgb(52, 74, 120), rgb(32, 46, 78)] as CFArray,
  locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
  backdrop,
  start: CGPoint(x: plate.minX, y: plate.maxY),
  end: CGPoint(x: plate.maxX, y: plate.minY),
  options: []
)
ctx.restoreGState()

// 紙面
let page = CGRect(x: 302, y: 212, width: 420, height: 580)
ctx.saveGState()
ctx.translateBy(x: page.midX, y: page.midY)
ctx.rotate(by: -4 * .pi / 180)
ctx.translateBy(x: -page.midX, y: -page.midY)

let pagePath = CGPath(roundedRect: page, cornerWidth: 20, cornerHeight: 20, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(12, 20, 40, 0.5))
ctx.addPath(pagePath)
ctx.setFillColor(rgb(252, 249, 240))
ctx.fillPath()
ctx.restoreGState()

// 紙のわずかな陰影
ctx.saveGState()
ctx.addPath(pagePath)
ctx.clip()
let paperShade = CGGradient(
  colorsSpace: space,
  colors: [rgb(252, 250, 243), rgb(236, 229, 214)] as CFArray,
  locations: [0, 1]
)!
ctx.drawLinearGradient(
  paperShade,
  start: CGPoint(x: page.minX, y: page.maxY),
  end: CGPoint(x: page.maxX, y: page.minY),
  options: []
)
ctx.restoreGState()

// 本文の行
ctx.setLineCap(.round)
ctx.setLineWidth(20)
ctx.setStrokeColor(rgb(198, 192, 178))
let lineLeft = page.minX + 54
let lineWidths: [CGFloat] = [312, 282, 312, 240, 312, 296, 198]
for (index, width) in lineWidths.enumerated() {
  let y = page.maxY - 104 - CGFloat(index) * 66
  ctx.move(to: CGPoint(x: lineLeft, y: y))
  ctx.addLine(to: CGPoint(x: lineLeft + width, y: y))
  ctx.strokePath()
}

// 蛍光ペン
ctx.saveGState()
ctx.setLineWidth(42)
ctx.setStrokeColor(rgb(255, 214, 92, 0.72))
let highlightY = page.maxY - 236
ctx.move(to: CGPoint(x: lineLeft - 4, y: highlightY))
ctx.addLine(to: CGPoint(x: lineLeft + 244, y: highlightY))
ctx.strokePath()
ctx.restoreGState()

// 手書きの線
ctx.saveGState()
ctx.setLineWidth(17)
ctx.setStrokeColor(rgb(58, 86, 150, 0.92))
ctx.move(to: CGPoint(x: lineLeft + 6, y: page.minY + 176))
ctx.addCurve(
  to: CGPoint(x: lineLeft + 318, y: page.minY + 206),
  control1: CGPoint(x: lineLeft + 118, y: page.minY + 266),
  control2: CGPoint(x: lineLeft + 196, y: page.minY + 116)
)
ctx.strokePath()
ctx.restoreGState()
ctx.restoreGState()

// 付箋（紙の右端にはみ出す）
ctx.saveGState()
let sticky = CGRect(x: 664, y: 470, width: 176, height: 176)
ctx.translateBy(x: sticky.midX, y: sticky.midY)
ctx.rotate(by: 7 * .pi / 180)
ctx.translateBy(x: -sticky.midX, y: -sticky.midY)
ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 24, color: rgb(12, 20, 40, 0.45))
ctx.addPath(CGPath(roundedRect: sticky, cornerWidth: 10, cornerHeight: 10, transform: nil))
ctx.setFillColor(rgb(255, 206, 70))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setLineWidth(13)
ctx.setStrokeColor(rgb(206, 154, 32, 0.85))
for index in 0..<3 {
  let y = sticky.maxY - 52 - CGFloat(index) * 44
  let width: CGFloat = index == 2 ? 72 : 110
  ctx.move(to: CGPoint(x: sticky.minX + 34, y: y))
  ctx.addLine(to: CGPoint(x: sticky.minX + 34 + width, y: y))
  ctx.strokePath()
}
ctx.restoreGState()

guard let image = ctx.makeImage() else {
  FileHandle.standardError.write(Data("画像を書き出せませんでした\n".utf8))
  exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
  FileHandle.standardError.write(Data("PNGの書き出し先を作れませんでした\n".utf8))
  exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  FileHandle.standardError.write(Data("PNGの保存に失敗しました\n".utf8))
  exit(1)
}
print("作成しました: \(url.path)")
