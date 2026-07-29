import Foundation
import WatchConnectivity

protocol WatchActionTransport: AnyObject {
  var isReachable: Bool { get }
  var onSnapshot: ((WatchSnapshotEnvelope) -> Void)? { get set }
  var onResult: ((WatchActionResultEnvelope) -> Void)? { get set }

  func activate()
  func submit(_ request: WatchActionRequestEnvelope) throws
}

final class WatchConnectivityClient: NSObject, WatchActionTransport {
  private let session: WCSession
  var onSnapshot: ((WatchSnapshotEnvelope) -> Void)?
  var onResult: ((WatchActionResultEnvelope) -> Void)?

  init(session: WCSession = .default) {
    self.session = session
    super.init()
    session.delegate = self
  }

  var isReachable: Bool {
    session.isReachable
  }

  func activate() {
    session.activate()
    consume(session.receivedApplicationContext)
  }

  func submit(_ request: WatchActionRequestEnvelope) throws {
    try request.validate()
    let payload = [
      "type": "action",
      "data": try request.encoded(),
    ] as [String: Any]
    if session.isReachable {
      session.sendMessage(
        payload,
        replyHandler: nil,
        errorHandler: { [weak session] _ in
          session?.transferUserInfo(payload)
        }
      )
    } else {
      session.transferUserInfo(payload)
    }
  }

  private func consume(_ payload: [String: Any]) {
    guard
      let type = payload["type"] as? String,
      let data = payload["data"] as? Data
    else {
      return
    }
    switch type {
    case "snapshot":
      guard let snapshot = try? WatchSnapshotEnvelope.decode(data) else {
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.onSnapshot?(snapshot)
      }
    case "actionResult":
      guard let result = try? WatchActionResultEnvelope.decode(data) else {
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.onResult?(result)
      }
    default:
      return
    }
  }
}

extension WatchConnectivityClient: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    consume(session.receivedApplicationContext)
  }

  func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    consume(applicationContext)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any]
  ) {
    consume(message)
  }

  func session(
    _ session: WCSession,
    didReceiveUserInfo userInfo: [String: Any] = [:]
  ) {
    consume(userInfo)
  }
}
