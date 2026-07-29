import Foundation
import XCTest

@testable import Buzz

final class WatchWireModelsTests: XCTestCase {

  func testSnapshotAndActionEnvelopesRoundTrip() throws {
    let snapshot = try sampleSnapshot()
    let decoded = try WatchSnapshotEnvelope.decode(snapshot.encoded())
    XCTAssertEqual(decoded, snapshot)

    let request = try WatchActionRequestEnvelope(
      actionID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      communityID: "zion",
      itemID: "approval-1",
      action: .pass,
      targetAgentPubkey: String(repeating: "b", count: 64)
    )
    XCTAssertEqual(
      try WatchActionRequestEnvelope.decode(request.encoded()),
      request
    )

    let result = try WatchActionResultEnvelope(
      actionID: request.actionID,
      communityID: "zion",
      itemID: "approval-1",
      outcome: .accepted,
      message: "Passed",
      resolvedAt: Date(timeIntervalSince1970: 1_775_000_010)
    )
    XCTAssertEqual(
      try WatchActionResultEnvelope.decode(result.encoded()),
      result
    )
  }

  func testUnknownSchemaIsRejected() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try sampleSnapshot().encoded())
        as? [String: Any]
    )
    object["version"] = 2
    let data = try JSONSerialization.data(withJSONObject: object)

    XCTAssertThrowsError(try WatchSnapshotEnvelope.decode(data))
  }

  func testSnapshotRejectsMoreThanTwentyItems() throws {
    let item = try sampleItem()
    XCTAssertThrowsError(
      try WatchSnapshotEnvelope(
        communityID: "zion",
        communityName: "Zion",
        generatedAt: Date(),
        items: Array(repeating: item, count: 21)
      )
    )
  }

  func testItemRejectsBodyOverTwoThousandUnicodeScalars() {
    XCTAssertThrowsError(
      try sampleItem(body: String(repeating: "🟣", count: 2_001))
    )
  }

  func testWirePayloadContainsNoSecretLikeKeys() throws {
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try sampleSnapshot().encoded())
    )
    let forbidden = Set(["secret", "privateKey", "token", "endpointGrant", "nsec"])

    XCTAssertTrue(secretKeys(in: object, forbidden: forbidden).isEmpty)
  }

  private func sampleSnapshot() throws -> WatchSnapshotEnvelope {
    try WatchSnapshotEnvelope(
      communityID: "zion",
      communityName: "Zion",
      generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
      items: [try sampleItem()]
    )
  }

  private func sampleItem(body: String = "Ship the release?") throws -> WatchWireInboxItem {
    try WatchWireInboxItem(
      itemID: "approval-1",
      type: .approval,
      communityID: "zion",
      channelID: "ops",
      title: "Approval",
      senderLabel: "Architect",
      channelLabel: "Operations",
      body: body,
      createdAt: Date(timeIntervalSince1970: 1_775_000_000),
      expiresAt: Date(timeIntervalSince1970: 1_775_000_600),
      sourceEventID: String(repeating: "a", count: 64),
      isTruncated: false,
      allowedActions: [.approve, .deny, .pass],
      eligibleAgents: [
        WatchWireAgentSummary(
          pubkey: String(repeating: "b", count: 64),
          displayName: "Builder",
          availability: .online,
          sortRank: 0
        )
      ]
    )
  }

  private func secretKeys(in value: Any, forbidden: Set<String>) -> [String] {
    if let object = value as? [String: Any] {
      return object.flatMap { key, nested in
        (forbidden.contains(key) ? [key] : []) + secretKeys(in: nested, forbidden: forbidden)
      }
    }
    if let array = value as? [Any] {
      return array.flatMap { secretKeys(in: $0, forbidden: forbidden) }
    }
    return []
  }
}
