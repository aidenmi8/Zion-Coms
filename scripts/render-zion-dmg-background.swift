import AppKit
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
  fputs("usage: render-zion-dmg-background.swift <transparent-lockup.png> <output.png>\n", stderr)
  exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
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

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let lockup = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fputs("could not load transparent lockup at \(sourceURL.path)\n", stderr)
  exit(1)
}

// CGContext draws CGImage pixels from a bottom-left image origin. Flip only
// this placed image so the transparent source remains upright in the
// top-left layout used by the rest of this composition.
context.saveGState()
context.translateBy(x: 150, y: 600)
context.scaleBy(x: 1, y: -1)
context.draw(lockup, in: CGRect(x: 0, y: 0, width: 420, height: 420))
context.restoreGState()

context.setStrokeColor(NSColor(calibratedRed: 0.82, green: 0.75, blue: 1, alpha: 0.9).cgColor)
context.setLineWidth(8)
context.setLineCap(.round)
context.move(to: CGPoint(x: 720, y: 500))
context.addLine(to: CGPoint(x: 900, y: 500))
context.move(to: CGPoint(x: 900, y: 500))
context.addLine(to: CGPoint(x: 862, y: 462))
context.move(to: CGPoint(x: 900, y: 500))
context.addLine(to: CGPoint(x: 862, y: 538))
context.strokePath()

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
let previousContext = NSGraphicsContext.current
NSGraphicsContext.current = graphicsContext
let attributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 26, weight: .medium),
  .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.89, blue: 1, alpha: 0.9),
]
("Drag to install" as NSString).draw(at: NSPoint(x: 754, y: 550), withAttributes: attributes)
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
