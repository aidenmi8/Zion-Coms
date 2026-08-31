import AppKit
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
  fputs("usage: render-zion-dmg-background.swift <output.png>\n", stderr)
  exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1320
let height = 1000
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
// The DMG background is a fully opaque composition; omit an alpha channel so
// Finder receives the same kind of flat PNG it previously expected.
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

guard let context = CGContext(
  data: nil,
  width: width,
  height: height,
  bitsPerComponent: 8,
  bytesPerRow: width * 4,
  space: colorSpace,
  bitmapInfo: bitmapInfo
) else {
  fputs("could not create output bitmap\n", stderr)
  exit(1)
}

context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)

let background = CGGradient(
  colorsSpace: colorSpace,
  colors: [
    NSColor(calibratedRed: 0.04, green: 0.02, blue: 0.09, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.25, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.06, green: 0.03, blue: 0.12, alpha: 1).cgColor,
  ] as CFArray,
  locations: [0, 0.48, 1]
)!
context.drawLinearGradient(
  background,
  start: CGPoint(x: 0, y: 0),
  end: CGPoint(x: 0, y: CGFloat(height)),
  options: []
)

let glow = CGGradient(
  colorsSpace: colorSpace,
  colors: [
    NSColor(calibratedRed: 0.73, green: 0.60, blue: 1, alpha: 0.22).cgColor,
    NSColor(calibratedRed: 0.73, green: 0.60, blue: 1, alpha: 0).cgColor,
  ] as CFArray,
  locations: [0, 1]
)!
context.setBlendMode(.screen)
context.drawRadialGradient(
  glow,
  startCenter: CGPoint(x: CGFloat(width) * 0.72, y: CGFloat(height) * 0.08),
  startRadius: 0,
  endCenter: CGPoint(x: CGFloat(width) * 0.72, y: CGFloat(height) * 0.08),
  endRadius: CGFloat(height) * 0.75,
  options: []
)
context.setBlendMode(.normal)

// Keep the artwork in the upper band of the image. Finder places the app and
// Applications alias around the vertical center of the DMG, so artwork here
// cannot sit behind their labels or icons.
func pointFromTopLeft(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
  CGPoint(x: x, y: y)
}

func drawPolygon(_ points: [(CGFloat, CGFloat)], color: CGColor) {
  let path = CGMutablePath()
  path.move(to: pointFromTopLeft(points[0].0, points[0].1))
  for point in points.dropFirst() {
    path.addLine(to: pointFromTopLeft(point.0, point.1))
  }
  path.closeSubpath()
  context.addPath(path)
  context.setFillColor(color)
  context.fillPath()
}

drawPolygon(
  [(165, 98), (285, 98), (235, 164), (115, 164)],
  color: NSColor(calibratedWhite: 0.98, alpha: 1).cgColor
)
drawPolygon(
  [(235, 178), (355, 178), (305, 244), (185, 244)],
  color: NSColor(calibratedWhite: 0.68, alpha: 1).cgColor
)

// The Finder item centers are x=191 and x=469 in the 660px DMG window. Keep
// the compact drag cue at their midpoint and on their center row.
let installArrowCenterX: CGFloat = 330
let installArrowY: CGFloat = 330
let installArrowHalfLength: CGFloat = 55
let installArrowHeadLength: CGFloat = 20
context.setStrokeColor(NSColor(calibratedRed: 0.82, green: 0.75, blue: 1, alpha: 0.9).cgColor)
context.setLineWidth(5)
context.setLineCap(.round)
context.move(to: pointFromTopLeft(installArrowCenterX - installArrowHalfLength, installArrowY))
context.addLine(to: pointFromTopLeft(installArrowCenterX + installArrowHalfLength, installArrowY))
context.move(to: pointFromTopLeft(installArrowCenterX + installArrowHalfLength, installArrowY))
context.addLine(to: pointFromTopLeft(installArrowCenterX + installArrowHalfLength - installArrowHeadLength, installArrowY - installArrowHeadLength))
context.move(to: pointFromTopLeft(installArrowCenterX + installArrowHalfLength, installArrowY))
context.addLine(to: pointFromTopLeft(installArrowCenterX + installArrowHalfLength - installArrowHeadLength, installArrowY + installArrowHeadLength))
context.strokePath()

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
let previousContext = NSGraphicsContext.current
NSGraphicsContext.current = graphicsContext
let attributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 54, weight: .semibold),
  .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.89, blue: 1, alpha: 0.9),
]
("Zion" as NSString).draw(at: NSPoint(x: 382, y: 125), withAttributes: attributes)

let instructionAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 26, weight: .medium),
  .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.89, blue: 1, alpha: 0.9),
]
("Drag to install" as NSString).draw(at: NSPoint(x: 238, y: 270), withAttributes: instructionAttributes)
NSGraphicsContext.current = previousContext

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        "public.png" as CFString,
        1,
        nil
      ) else {
  fputs("could not write output bitmap\n", stderr)
  exit(1)
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  fputs("could not finalize output PNG\n", stderr)
  exit(1)
}
