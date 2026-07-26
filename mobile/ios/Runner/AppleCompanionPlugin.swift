import Flutter
import Foundation

@MainActor
final class AppleCompanionPlugin: NSObject, @preconcurrency FlutterStreamHandler {
  private let registrar: ApplicationRemoteNotificationRegistrar
  private let service: PushEnrollmentService
  private var eventSink: FlutterEventSink?

  init(binaryMessenger: FlutterBinaryMessenger) {
    let registrar = ApplicationRemoteNotificationRegistrar()
    self.registrar = registrar
    service = PushEnrollmentService(
      permission: SystemNotificationPermissionProvider(),
      registrar: registrar,
      appAttest: SystemAppAttestProvider(),
      gateway: URLSessionPushGateway(),
      keychain: KeychainStore()
    )
    super.init()

    let methodChannel = FlutterMethodChannel(
      name: "zion/apple_companion",
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "not_ready", message: nil, details: nil))
        return
      }
      Task { @MainActor in
        await self.handle(call, result: result)
      }
    }
    let eventChannel = FlutterEventChannel(
      name: "zion/apple_companion/events",
      binaryMessenger: binaryMessenger
    )
    eventChannel.setStreamHandler(self)
    registrar.onTokenChanged = { [weak self] in
      self?.eventSink?(["endpointEpoch": -1])
    }
  }

  func didRegisterForRemoteNotifications(deviceToken: Data) {
    registrar.didRegister(token: deviceToken)
  }

  func didFailToRegisterForRemoteNotifications(_ error: Error) {
    registrar.didFail(error)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    do {
      switch call.method {
      case "notificationStatus":
        result((await service.notificationStatus()).rawValue)
      case "enableNotifications":
        let context = try Self.context(call.arguments)
        result(Self.wire(try await service.enableNotifications(context)))
      case "currentEndpointGrant":
        let context = try Self.context(call.arguments)
        result(service.currentEndpointGrant(context).map(Self.wire))
      case "revokeEndpoint":
        let context = try Self.context(call.arguments)
        try await service.revokeEndpoint(context)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as PushEnrollmentError {
      result(
        FlutterError(
          code: Self.code(error),
          message: Self.message(error),
          details: nil
        )
      )
    } catch {
      result(
        FlutterError(
          code: "not_ready",
          message: "Push enrollment is temporarily unavailable.",
          details: nil
        )
      )
    }
  }

  private static func context(_ arguments: Any?) throws -> PushEnrollmentContext {
    guard
      let values = arguments as? [String: Any],
      let gateway = values["gatewayOrigin"] as? String,
      let gatewayURL = URL(string: gateway),
      gatewayURL.scheme == "https",
      gatewayURL.path.isEmpty,
      gatewayURL.query == nil,
      gatewayURL.fragment == nil,
      let relayPubkey = values["relayPubkey"] as? String,
      relayPubkey.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      let appProfileID = values["appProfileId"] as? String,
      ["buzz-ios-production", "buzz-ios-sandbox"].contains(appProfileID),
      let expiresAt = values["expiresAt"] as? Int
    else {
      throw PushEnrollmentError.invalidResponse
    }
    return PushEnrollmentContext(
      gatewayOrigin: gatewayURL,
      relayPubkey: relayPubkey,
      appProfileID: appProfileID,
      expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))
    )
  }

  private static func wire(_ grant: PushEndpointGrant) -> [String: Any] {
    [
      "endpointGrant": grant.value,
      "appProfileId": grant.appProfileID,
      "endpointEpoch": grant.endpointEpoch,
      "generation": grant.generation,
      "expiresAt": Int(grant.expiresAt.timeIntervalSince1970),
    ]
  }

  private static func code(_ error: PushEnrollmentError) -> String {
    switch error {
    case .unsupported: "unsupported"
    case .denied: "denied"
    case .notReady: "not_ready"
    case .invalidResponse: "invalid_response"
    case .gateway(let code): code
    }
  }

  private static func message(_ error: PushEnrollmentError) -> String? {
    switch error {
    case .denied:
      "Notifications are disabled in iOS Settings."
    case .unsupported:
      "App Attest is unavailable on this device."
    case .notReady:
      "APNs registration is not ready."
    case .invalidResponse:
      "The push service returned an invalid response."
    case .gateway:
      "The push service could not complete enrollment."
    }
  }
}
