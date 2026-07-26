import Foundation
import XCTest

@testable import Buzz

final class WatchSessionBridgeTests: XCTestCase {

  func testReachableWatchReceivesImmediateSnapshotMessage() throws {
    let session = FakeWatchSessionTransport(isReachable: true)
    let storage = FakeWatchBridgeStorage()
    let bridge = WatchSessionBridge(session: session, storage: storage)
    let snapshot = try sampleSnapshot()

    try bridge.publish(snapshot)

    XCTAssertEqual(session.sentMessages.count, 1)
    XCTAssertEqual(session.transferredUserInfo.count, 0)
    XCTAssertEqual(session.applicationContexts.count, 1)
    XCTAssertEqual(storage.snapshotReplacements, 1)
    XCTAssertEqual(try payloadSnapshot(session.sentMessages[0]), snapshot)
  }

  func testUnreachableWatchQueuesSnapshotAndUpdatesApplicationContext() throws {
    let session = FakeWatchSessionTransport(isReachable: false)
    let bridge = WatchSessionBridge(
      session: session,
      storage: FakeWatchBridgeStorage()
    )
    let snapshot = try sampleSnapshot()

    try bridge.publish(snapshot)

    XCTAssertEqual(session.sentMessages.count, 0)
    XCTAssertEqual(session.transferredUserInfo.count, 1)
    XCTAssertEqual(session.applicationContexts.count, 1)
    XCTAssertEqual(
      try payloadSnapshot(session.transferredUserInfo[0]),
      snapshot
    )
  }

  func testNewSnapshotAtomicallyReplacesOlderCommunityData() throws {
    let storage = FakeWatchBridgeStorage()
    let bridge = WatchSessionBridge(
      session: FakeWatchSessionTransport(isReachable: true),
      storage: storage
    )
    try bridge.publish(try sampleSnapshot(communityID: "old"))
    let replacement = try sampleSnapshot(communityID: "new")

    try bridge.publish(replacement)

    XCTAssertEqual(storage.snapshotReplacements, 2)
    XCTAssertEqual(
      try WatchSnapshotEnvelope.decode(XCTUnwrap(storage.snapshotData)),
      replacement
    )
  }

  func testDuplicateActionIDsAreForwardedOnce() throws {
    let session = FakeWatchSessionTransport(isReachable: true)
    let storage = FakeWatchBridgeStorage()
    let bridge = WatchSessionBridge(session: session, storage: storage)
    var forwarded: [WatchActionRequestEnvelope] = []
    bridge.setActionHandler { forwarded.append($0) }
    let request = try actionRequest()
    let message = ["type": "action", "data": try request.encoded()] as [String: Any]

    let firstReply = session.receive(message)
    let duplicateReply = session.receive(message)

    XCTAssertEqual(forwarded, [request])
    XCTAssertEqual(firstReply?["accepted"] as? Bool, true)
    XCTAssertEqual(duplicateReply?["accepted"] as? Bool, true)
    XCTAssertEqual(storage.pendingActions.count, 1)
  }

  func testMalformedAndOversizedActionsAreRejected() throws {
    let session = FakeWatchSessionTransport(isReachable: true)
    let bridge = WatchSessionBridge(
      session: session,
      storage: FakeWatchBridgeStorage()
    )

    let malformed = session.receive(["type": "action", "data": Data("{}".utf8)])
    let oversized = session.receive([
      "type": "action",
      "data": Data(repeating: 0x41, count: WatchSessionBridge.maxActionBytes + 1),
    ])

    XCTAssertEqual(malformed?["accepted"] as? Bool, false)
    XCTAssertEqual(oversized?["accepted"] as? Bool, false)
    withExtendedLifetime(bridge) {}
  }

  func testCommunityClearPublishesAnEmptySnapshot() throws {
    let session = FakeWatchSessionTransport(isReachable: true)
    let bridge = WatchSessionBridge(
      session: session,
      storage: FakeWatchBridgeStorage()
    )
    try bridge.publish(try sampleSnapshot())

    try bridge.clearSnapshot()

    let cleared = try payloadSnapshot(XCTUnwrap(session.applicationContexts.last))
    XCTAssertEqual(cleared.communityID, "zion")
    XCTAssertTrue(cleared.items.isEmpty)
  }

  func testPendingActionReplaysWhenFlutterBecomesReady() throws {
    let session = FakeWatchSessionTransport(isReachable: false)
    let storage = FakeWatchBridgeStorage()
    let bridge = WatchSessionBridge(session: session, storage: storage)
    let request = try actionRequest()

    _ = session.receive(["type": "action", "data": try request.encoded()])
    XCTAssertEqual(storage.pendingActions.count, 1)

    var replayed: [WatchActionRequestEnvelope] = []
    bridge.setActionHandler { replayed.append($0) }

    XCTAssertEqual(replayed, [request])
  }

  private func sampleSnapshot(
    communityID: String = "zion"
  ) throws -> WatchSnapshotEnvelope {
    try WatchSnapshotEnvelope(
      communityID: communityID,
      communityName: communityID.capitalized,
      generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
      items: []
    )
  }

  private func actionRequest() throws -> WatchActionRequestEnvelope {
    try WatchActionRequestEnvelope(
      actionID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      communityID: "zion",
      itemID: "approval-1",
      action: .approve,
      targetAgentPubkey: nil
    )
  }

  private func payloadSnapshot(
    _ payload: [String: Any]
  ) throws -> WatchSnapshotEnvelope {
    let data = try XCTUnwrap(payload["data"] as? Data)
    return try WatchSnapshotEnvelope.decode(data)
  }
}

private final class FakeWatchSessionTransport: WatchSessionTransport {
  var isReachable: Bool
  var onMessage: (([String: Any], (([String: Any]) -> Void)?) -> Void)?
  private(set) var sentMessages: [[String: Any]] = []
  private(set) var transferredUserInfo: [[String: Any]] = []
  private(set) var applicationContexts: [[String: Any]] = []

  init(isReachable: Bool) {
    self.isReachable = isReachable
  }

  func activate() {}

  func sendMessage(_ message: [String: Any]) {
    sentMessages.append(message)
  }

  func transferUserInfo(_ userInfo: [String: Any]) {
    transferredUserInfo.append(userInfo)
  }

  func updateApplicationContext(_ applicationContext: [String: Any]) throws {
    applicationContexts.append(applicationContext)
  }

  func receive(_ message: [String: Any]) -> [String: Any]? {
    var reply: [String: Any]?
    onMessage?(message) { reply = $0 }
    return reply
  }
}

private final class FakeWatchBridgeStorage: WatchBridgeStoring {
  var snapshotData: Data?
  var pendingActions: [Data] = []
  var snapshotReplacements = 0

  func loadSnapshot() throws -> Data? {
    snapshotData
  }

  func replaceSnapshot(with data: Data) throws {
    snapshotReplacements += 1
    snapshotData = data
  }

  func loadPendingActions() throws -> [Data] {
    pendingActions
  }

  func replacePendingActions(with actions: [Data]) throws {
    pendingActions = actions
  }
}
