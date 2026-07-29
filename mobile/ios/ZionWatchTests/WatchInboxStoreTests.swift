import Foundation
import XCTest

@testable import ZionWatch

@MainActor
final class WatchInboxStoreTests: XCTestCase {
  func testCachedSnapshotStartsOfflineAndReadOnly() throws {
    let cache = MemoryWatchInboxCache(snapshot: try snapshot())
    let transport = FakeWatchActionTransport(isReachable: false)

    let store = WatchInboxStore(cache: cache, transport: transport)

    XCTAssertEqual(store.items.map(\.itemID), ["approval", "dm", "mention"])
    XCTAssertTrue(store.isShowingCachedData)
    XCTAssertTrue(store.isReadOnly)
  }

  func testLiveSnapshotReplacesOldCommunityAndSortsApprovalFirst() throws {
    let cache = MemoryWatchInboxCache(snapshot: try snapshot(communityID: "old"))
    let transport = FakeWatchActionTransport(isReachable: true)
    let store = WatchInboxStore(cache: cache, transport: transport)
    let replacement = try snapshot(communityID: "new")

    transport.receive(replacement)

    XCTAssertEqual(store.communityID, "new")
    XCTAssertEqual(store.items.map(\.itemID), ["approval", "dm", "mention"])
    XCTAssertFalse(store.isShowingCachedData)
    XCTAssertFalse(store.isReadOnly)
    XCTAssertEqual(cache.snapshot?.communityID, "new")
  }

  func testMutatingActionsRequireConfirmationAndDisableRepeatSubmission() throws {
    let transport = FakeWatchActionTransport(isReachable: true)
    let store = WatchInboxStore(
      cache: MemoryWatchInboxCache(),
      transport: transport,
      uuid: { UUID(uuidString: "10000000-0000-4000-8000-000000000001")! }
    )
    transport.receive(try snapshot())

    store.requestConfirmation(itemID: "approval", action: .approve)
    XCTAssertEqual(store.confirmation?.action, .approve)
    store.confirmAction()
    store.confirmAction()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(store.actionState(for: "approval"), .sending)
  }

  func testOfflineActionQueuesThenTerminalResultRemovesItem() throws {
    let transport = FakeWatchActionTransport(isReachable: false)
    let store = WatchInboxStore(
      cache: MemoryWatchInboxCache(),
      transport: transport
    )
    transport.receive(try snapshot())
    store.requestConfirmation(itemID: "approval", action: .deny)
    store.confirmAction()
    let request = try XCTUnwrap(transport.requests.first)

    XCTAssertEqual(store.actionState(for: "approval"), .queued)

    transport.receive(
      try WatchActionResultEnvelope(
        actionID: request.actionID,
        communityID: request.communityID,
        itemID: request.itemID,
        outcome: .accepted,
        message: "Denied",
        resolvedAt: Date()
      )
    )

    XCTAssertEqual(store.actionState(for: "approval"), .succeeded("Denied"))
    XCTAssertFalse(store.items.contains { $0.itemID == "approval" })
  }

  func testRetryableResultKeepsItemAndExposesFailure() throws {
    let transport = FakeWatchActionTransport(isReachable: true)
    let store = WatchInboxStore(
      cache: MemoryWatchInboxCache(),
      transport: transport
    )
    transport.receive(try snapshot())
    store.requestConfirmation(itemID: "approval", action: .approve)
    store.confirmAction()
    let request = try XCTUnwrap(transport.requests.first)

    transport.receive(
      try WatchActionResultEnvelope(
        actionID: request.actionID,
        communityID: request.communityID,
        itemID: request.itemID,
        outcome: .retryable,
        message: "Try again",
        resolvedAt: Date()
      )
    )

    XCTAssertEqual(store.actionState(for: "approval"), .failed("Try again"))
    XCTAssertTrue(store.items.contains { $0.itemID == "approval" })
  }

  func testPassRequiresAnEligibleSelectedAgent() throws {
    let transport = FakeWatchActionTransport(isReachable: true)
    let store = WatchInboxStore(
      cache: MemoryWatchInboxCache(),
      transport: transport
    )
    transport.receive(try snapshot())

    store.requestPass(itemID: "approval", targetAgentPubkey: "not-eligible")
    XCTAssertNil(store.confirmation)

    store.requestPass(
      itemID: "approval",
      targetAgentPubkey: String(repeating: "b", count: 64)
    )
    XCTAssertEqual(store.confirmation?.action, .pass)
    store.confirmAction()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(
      transport.requests.first?.targetAgentPubkey,
      String(repeating: "b", count: 64)
    )
  }

  func testOpenOnPhoneSendsADeepLinkActionWithoutConfirmation() throws {
    let transport = FakeWatchActionTransport(isReachable: true)
    let store = WatchInboxStore(
      cache: MemoryWatchInboxCache(),
      transport: transport
    )
    transport.receive(try snapshot())

    store.openOnPhone(itemID: "dm")

    XCTAssertNil(store.confirmation)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.action, .openOnPhone)
    XCTAssertEqual(transport.requests.first?.itemID, "dm")
  }

  private func snapshot(
    communityID: String = "zion"
  ) throws -> WatchSnapshotEnvelope {
    try WatchSnapshotEnvelope(
      communityID: communityID,
      communityName: communityID.capitalized,
      generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
      items: [
        try item(
          id: "mention",
          type: .mention,
          communityID: communityID,
          createdAt: 300
        ),
        try item(
          id: "dm",
          type: .directMessage,
          communityID: communityID,
          createdAt: 400
        ),
        try item(
          id: "approval",
          type: .approval,
          communityID: communityID,
          createdAt: 100
        ),
      ]
    )
  }

  private func item(
    id: String,
    type: WatchWireItemType,
    communityID: String,
    createdAt: TimeInterval
  ) throws -> WatchWireInboxItem {
    try WatchWireInboxItem(
      itemID: id,
      type: type,
      communityID: communityID,
      channelID: "channel",
      title: type == .approval ? "Approval" : "Message",
      senderLabel: "Architect",
      channelLabel: "Operations",
      body: "Review this request",
      createdAt: Date(timeIntervalSince1970: createdAt),
      expiresAt: type == .approval
        ? Date(timeIntervalSince1970: 1_900_000_000)
        : nil,
      sourceEventID: String(repeating: "a", count: 64),
      isTruncated: false,
      allowedActions: type == .approval
        ? [.approve, .deny, .pass, .openOnPhone]
        : [.openOnPhone],
      eligibleAgents: type == .approval
        ? [
          WatchWireAgentSummary(
            pubkey: String(repeating: "b", count: 64),
            displayName: "Builder",
            availability: .online,
            sortRank: 0
          )
        ]
        : []
    )
  }
}

private final class MemoryWatchInboxCache: WatchInboxCaching {
  var snapshot: WatchSnapshotEnvelope?

  init(snapshot: WatchSnapshotEnvelope? = nil) {
    self.snapshot = snapshot
  }

  func load() throws -> WatchSnapshotEnvelope? {
    snapshot
  }

  func replace(with snapshot: WatchSnapshotEnvelope) throws {
    self.snapshot = snapshot
  }
}

private final class FakeWatchActionTransport: WatchActionTransport {
  var isReachable: Bool
  var onSnapshot: ((WatchSnapshotEnvelope) -> Void)?
  var onResult: ((WatchActionResultEnvelope) -> Void)?
  private(set) var requests: [WatchActionRequestEnvelope] = []

  init(isReachable: Bool) {
    self.isReachable = isReachable
  }

  func activate() {}

  func submit(_ request: WatchActionRequestEnvelope) throws {
    requests.append(request)
  }

  func receive(_ snapshot: WatchSnapshotEnvelope) {
    onSnapshot?(snapshot)
  }

  func receive(_ result: WatchActionResultEnvelope) {
    onResult?(result)
  }
}
