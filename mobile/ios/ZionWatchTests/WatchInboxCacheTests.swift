import Foundation
import XCTest

@testable import ZionWatch

final class WatchInboxCacheTests: XCTestCase {
  func testRoundTripsProtectedSnapshotData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let cache = WatchInboxCache(directory: directory)
    let expected = try snapshot(communityID: "zion")

    try cache.replace(with: expected)

    XCTAssertEqual(try cache.load(), expected)
  }

  func testReplacementNeverMergesAnotherCommunity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let cache = WatchInboxCache(directory: directory)
    try cache.replace(with: try snapshot(communityID: "old"))

    try cache.replace(with: try snapshot(communityID: "new"))

    XCTAssertEqual(try cache.load()?.communityID, "new")
  }

  private func snapshot(communityID: String) throws -> WatchSnapshotEnvelope {
    try WatchSnapshotEnvelope(
      communityID: communityID,
      communityName: communityID.capitalized,
      generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
      items: []
    )
  }
}
