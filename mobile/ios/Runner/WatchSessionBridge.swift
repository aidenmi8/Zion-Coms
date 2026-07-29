import Foundation
import WatchConnectivity

protocol WatchSessionTransport: AnyObject {
  var isReachable: Bool { get }
  var onMessage: (([String: Any], (([String: Any]) -> Void)?) -> Void)? { get set }

  func activate()
  func sendMessage(_ message: [String: Any])
  func transferUserInfo(_ userInfo: [String: Any])
  func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

protocol WatchBridgeStoring: AnyObject {
  func loadSnapshot() throws -> Data?
  func replaceSnapshot(with data: Data) throws
  func loadPendingActions() throws -> [Data]
  func replacePendingActions(with actions: [Data]) throws
}

final class WatchSessionBridge {
  static let maxActionBytes = 16 * 1_024

  private let session: WatchSessionTransport
  private let storage: WatchBridgeStoring
  private var latestSnapshot: WatchSnapshotEnvelope?
  private var pendingActions: [WatchActionRequestEnvelope] = []
  private var knownActionIDs: Set<UUID> = []
  private var forwardedActionIDs: Set<UUID> = []
  private var actionHandler: ((WatchActionRequestEnvelope) -> Void)?

  init(session: WatchSessionTransport, storage: WatchBridgeStoring) {
    self.session = session
    self.storage = storage
    if
      let data = try? storage.loadSnapshot(),
      let snapshot = try? WatchSnapshotEnvelope.decode(data)
    {
      latestSnapshot = snapshot
    }
    if let stored = try? storage.loadPendingActions() {
      pendingActions = stored.compactMap {
        try? WatchActionRequestEnvelope.decode($0)
      }
      knownActionIDs = Set(pendingActions.map(\.actionID))
    }
    session.onMessage = { [weak self] message, reply in
      self?.receive(message, reply: reply)
    }
    session.activate()
  }

  convenience init?() {
    guard WCSession.isSupported() else { return nil }
    self.init(
      session: SystemWatchSessionTransport(session: .default),
      storage: FileWatchBridgeStorage()
    )
  }

  func publish(_ snapshot: WatchSnapshotEnvelope) throws {
    try snapshot.validate()
    let data = try snapshot.encoded()
    try storage.replaceSnapshot(with: data)
    latestSnapshot = snapshot
    try deliverSnapshot(data)
  }

  func clearSnapshot() throws {
    let empty = try WatchSnapshotEnvelope(
      communityID: latestSnapshot?.communityID ?? "",
      communityName: latestSnapshot?.communityName ?? "",
      generatedAt: Date(),
      items: []
    )
    try publish(empty)
  }

  func setActionHandler(
    _ handler: ((WatchActionRequestEnvelope) -> Void)?
  ) {
    actionHandler = handler
    guard let handler else { return }
    for request in pendingActions
    where forwardedActionIDs.insert(request.actionID).inserted {
      handler(request)
    }
  }

  func complete(_ result: WatchActionResultEnvelope) throws {
    try result.validate()
    pendingActions.removeAll { $0.actionID == result.actionID }
    try persistPendingActions()
    let payload = [
      "type": "actionResult",
      "data": try result.encoded(),
    ] as [String: Any]
    if session.isReachable {
      session.sendMessage(payload)
    } else {
      session.transferUserInfo(payload)
    }
  }

  private func deliverSnapshot(_ data: Data) throws {
    let payload = ["type": "snapshot", "data": data] as [String: Any]
    try session.updateApplicationContext(payload)
    if session.isReachable {
      session.sendMessage(payload)
    } else {
      session.transferUserInfo(payload)
    }
  }

  private func receive(
    _ message: [String: Any],
    reply: (([String: Any]) -> Void)?
  ) {
    guard
      message["type"] as? String == "action",
      let data = message["data"] as? Data,
      data.count <= Self.maxActionBytes,
      let request = try? WatchActionRequestEnvelope.decode(data)
    else {
      reply?(["accepted": false])
      return
    }
    if knownActionIDs.insert(request.actionID).inserted {
      pendingActions.append(request)
      do {
        try persistPendingActions()
      } catch {
        pendingActions.removeAll { $0.actionID == request.actionID }
        knownActionIDs.remove(request.actionID)
        reply?(["accepted": false])
        return
      }
      if
        let actionHandler,
        forwardedActionIDs.insert(request.actionID).inserted
      {
        actionHandler(request)
      }
    }
    reply?(["accepted": true])
  }

  private func persistPendingActions() throws {
    try storage.replacePendingActions(
      with: pendingActions.map { try $0.encoded() }
    )
  }
}

final class FileWatchBridgeStorage: WatchBridgeStoring {
  private struct PendingFile: Codable {
    let actions: [Data]
  }

  private let fileManager: FileManager
  private let directory: URL

  init(
    directory: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.directory =
      directory
      ?? fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first?
      .appendingPathComponent("zion-watch", isDirectory: true)
      ?? fileManager.temporaryDirectory.appendingPathComponent(
        "zion-watch",
        isDirectory: true
      )
  }

  func loadSnapshot() throws -> Data? {
    try read(snapshotURL)
  }

  func replaceSnapshot(with data: Data) throws {
    try writeProtected(data, to: snapshotURL)
  }

  func loadPendingActions() throws -> [Data] {
    guard let data = try read(actionsURL) else { return [] }
    return try JSONDecoder().decode(PendingFile.self, from: data).actions
  }

  func replacePendingActions(with actions: [Data]) throws {
    try writeProtected(
      try JSONEncoder().encode(PendingFile(actions: actions)),
      to: actionsURL
    )
  }

  private var snapshotURL: URL {
    directory.appendingPathComponent("snapshot.json")
  }

  private var actionsURL: URL {
    directory.appendingPathComponent("pending-actions.json")
  }

  private func read(_ url: URL) throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }

  private func writeProtected(_ data: Data, to url: URL) throws {
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ]
    )
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }
}

final class SystemWatchSessionTransport: NSObject, WatchSessionTransport {
  private let session: WCSession
  var onMessage: (([String: Any], (([String: Any]) -> Void)?) -> Void)?

  init(session: WCSession) {
    self.session = session
    super.init()
    session.delegate = self
  }

  var isReachable: Bool {
    session.isReachable
  }

  func activate() {
    session.activate()
  }

  func sendMessage(_ message: [String: Any]) {
    session.sendMessage(message, replyHandler: nil, errorHandler: nil)
  }

  func transferUserInfo(_ userInfo: [String: Any]) {
    session.transferUserInfo(userInfo)
  }

  func updateApplicationContext(_ applicationContext: [String: Any]) throws {
    try session.updateApplicationContext(applicationContext)
  }
}

extension SystemWatchSessionTransport: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.onMessage?(message, replyHandler)
    }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    DispatchQueue.main.async { [weak self] in
      self?.onMessage?(userInfo, nil)
    }
  }
}
