import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 4,
      let size = Int(CommandLine.arguments[3]),
      size > 0 else {
  fputs("usage: render-zion-icon.swift <source.png> <output.png> <size>\n", stderr)
  exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
  fputs("could not load source or create RGBA output bitmap\n", stderr)
  exit(1)
}

context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let outputImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        "public.png" as CFString,
        1,
        nil
      ) else {
  fputs("could not write output bitmap\n", stderr)
  exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
  fputs("could not finalize output PNG\n", stderr)
  exit(1)
}
