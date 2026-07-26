import SwiftUI

enum ZionBranding {
  static let wordmarkAssetName = "SentraWordmark"
  static let appIconAssetName = "AppIcon"

  static let backgroundRGB: UInt32 = 0x100A18
  static let foregroundRGB: UInt32 = 0xF3EDFF
  static let secondaryRGB: UInt32 = 0xB8A7CC
  static let violetRGB: UInt32 = 0xA78BFA
}

struct ZionBrandMark: View {
  var height: CGFloat = 46

  var body: some View {
    Image(ZionBranding.wordmarkAssetName)
      .resizable()
      .scaledToFit()
      .frame(height: height)
      .accessibilityLabel("Sentra")
  }
}

extension Color {
  init(zionRGB value: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255,
      opacity: opacity
    )
  }
}
