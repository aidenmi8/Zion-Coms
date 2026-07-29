import Combine
import Foundation

enum WatchItemActionState: Equatable {
  case idle
  case queued
  case sending
  case succeeded(String)
  case failed(String)

  var isInFlight: Bool {
    self == .queued || self == .sending
  }
}

struct WatchActionConfirmation: Equatable {
  let itemID: String
  let action: WatchWireAction
  let targetAgentPubkey: String?
}

@MainActor
final class WatchInboxStore: ObservableObject {
  @Published private(set) var communityID = ""
  @Published private(set) var communityName = ""
  @Published private(set) var items: [WatchWireInboxItem] = []
  @Published private(set) var isShowingCachedData = false
  @Published private(set) var isReadOnly = true
  @Published private(set) var confirmation: WatchActionConfirmation?

  private let cache: WatchInboxCaching
  private let transport: WatchActionTransport
  private let now: () -> Date
  private let uuid: () -> UUID
  private var actionStates: [String: WatchItemActionState] = [:]
  private var itemIDByActionID: [UUID: String] = [:]
  private var terminalItemIDs: Set<String> = []

  init(
    cache: WatchInboxCaching,
    transport: WatchActionTransport,
    now: @escaping () -> Date = Date.init,
    uuid: @escaping () -> UUID = UUID.init
  ) {
    self.cache = cache
    self.transport = transport
    self.now = now
    self.uuid = uuid

    if let snapshot = try? cache.load() {
      apply(snapshot, isCached: true)
    }
    transport.onSnapshot = { [weak self] snapshot in
      self?.receive(snapshot)
    }
    transport.onResult = { [weak self] result in
      self?.receive(result)
    }
    transport.activate()
  }

  func actionState(for itemID: String) -> WatchItemActionState {
    actionStates[itemID] ?? .idle
  }

  func requestConfirmation(itemID: String, action: WatchWireAction) {
    guard
      !isReadOnly,
      action == .approve || action == .deny,
      let item = item(itemID),
      item.type == .approval,
      item.allowedActions.contains(action),
      !actionState(for: itemID).isInFlight
    else {
      return
    }
    confirmation = WatchActionConfirmation(
      itemID: itemID,
      action: action,
      targetAgentPubkey: nil
    )
  }

  func requestPass(itemID: String, targetAgentPubkey: String) {
    guard
      !isReadOnly,
      let item = item(itemID),
      item.type == .approval,
      item.allowedActions.contains(.pass),
      item.eligibleAgents.contains(where: {
        $0.pubkey == targetAgentPubkey
      }),
      !actionState(for: itemID).isInFlight
    else {
      return
    }
    confirmation = WatchActionConfirmation(
      itemID: itemID,
      action: .pass,
      targetAgentPubkey: targetAgentPubkey
    )
  }

  func cancelConfirmation() {
    confirmation = nil
  }

  func confirmAction() {
    guard let confirmation else { return }
    self.confirmation = nil
    submit(
      itemID: confirmation.itemID,
      action: confirmation.action,
      targetAgentPubkey: confirmation.targetAgentPubkey
    )
  }

  func openOnPhone(itemID: String) {
    guard
      !isReadOnly,
      let item = item(itemID),
      item.allowedActions.contains(.openOnPhone),
      !actionState(for: itemID).isInFlight
    else {
      return
    }
    submit(itemID: itemID, action: .openOnPhone, targetAgentPubkey: nil)
  }

  private func submit(
    itemID: String,
    action: WatchWireAction,
    targetAgentPubkey: String?
  ) {
    guard
      let item = item(itemID),
      !actionState(for: itemID).isInFlight
    else {
      return
    }
    do {
      let request = try WatchActionRequestEnvelope(
        actionID: uuid(),
        communityID: communityID,
        itemID: item.itemID,
        action: action,
        targetAgentPubkey: targetAgentPubkey
      )
      itemIDByActionID[request.actionID] = item.itemID
      actionStates[item.itemID] = transport.isReachable ? .sending : .queued
      objectWillChange.send()
      try transport.submit(request)
    } catch {
      actionStates[item.itemID] = .failed("Could not send. Try again.")
      objectWillChange.send()
    }
  }

  private func receive(_ snapshot: WatchSnapshotEnvelope) {
    do {
      try cache.replace(with: snapshot)
      apply(snapshot, isCached: false)
    } catch {
      return
    }
  }

  private func receive(_ result: WatchActionResultEnvelope) {
    guard
      result.communityID == communityID,
      itemIDByActionID[result.actionID] == result.itemID
    else {
      return
    }
    switch result.outcome {
    case .accepted, .alreadyResolved:
      actionStates[result.itemID] = .succeeded(result.message)
      terminalItemIDs.insert(result.itemID)
      items.removeAll { $0.itemID == result.itemID }
      persistVisibleSnapshot()
    case .rejected, .retryable:
      actionStates[result.itemID] = .failed(result.message)
    }
    objectWillChange.send()
  }

  private func apply(
    _ snapshot: WatchSnapshotEnvelope,
    isCached: Bool
  ) {
    if snapshot.communityID != communityID {
      terminalItemIDs.removeAll()
      actionStates.removeAll()
      itemIDByActionID.removeAll()
    }
    communityID = snapshot.communityID
    communityName = snapshot.communityName
    items = snapshot.items
      .filter { !terminalItemIDs.contains($0.itemID) }
      .sorted(by: Self.precedes)
      .prefix(watchWireMaximumItems)
      .map(\.self)
    isShowingCachedData = isCached
    isReadOnly = isCached
  }

  private func item(_ itemID: String) -> WatchWireInboxItem? {
    items.first { $0.itemID == itemID }
  }

  private func persistVisibleSnapshot() {
    guard
      let snapshot = try? WatchSnapshotEnvelope(
        communityID: communityID,
        communityName: communityName,
        generatedAt: now(),
        items: items
      )
    else {
      return
    }
    try? cache.replace(with: snapshot)
  }

  private static func precedes(
    _ left: WatchWireInboxItem,
    _ right: WatchWireInboxItem
  ) -> Bool {
    let leftRank = left.type == .approval ? 0 : 1
    let rightRank = right.type == .approval ? 0 : 1
    if leftRank != rightRank { return leftRank < rightRank }
    if left.createdAt != right.createdAt {
      return left.createdAt > right.createdAt
    }
    return left.itemID < right.itemID
  }
}
