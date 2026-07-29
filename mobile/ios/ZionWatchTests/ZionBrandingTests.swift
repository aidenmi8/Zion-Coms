import XCTest

@testable import ZionWatch

final class ZionBrandingTests: XCTestCase {
  func testUsesApprovedZionOrbitIdentity() {
    XCTAssertEqual(ZionBranding.wordmarkAssetName, "SentraWordmark")
    XCTAssertEqual(ZionBranding.appIconAssetName, "AppIcon")
    XCTAssertEqual(ZionBranding.backgroundRGB, 0x100A18)
    XCTAssertEqual(ZionBranding.foregroundRGB, 0xF3EDFF)
    XCTAssertEqual(ZionBranding.secondaryRGB, 0xB8A7CC)
    XCTAssertEqual(ZionBranding.violetRGB, 0xA78BFA)
  }
}
