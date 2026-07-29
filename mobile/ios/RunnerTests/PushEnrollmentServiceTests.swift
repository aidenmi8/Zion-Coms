import Foundation
import UserNotifications
import XCTest

@testable import Buzz

@MainActor
final class PushEnrollmentServiceTests: XCTestCase {

  func testPermissionIsRequestedOnlyByExplicitEnableAndRegistrationWaitsForGrant() async throws {
    let permission = FakeNotificationPermission(status: .notDetermined, grants: true)
    let registrar = FakeRemoteNotificationRegistrar(tokens: [Data([0x01, 0x02])])
    let service = makeService(permission: permission, registrar: registrar)

    let status = await service.notificationStatus()
    XCTAssertEqual(status, .notDetermined)
    XCTAssertEqual(permission.requestCount, 0)
    XCTAssertEqual(registrar.registerCount, 0)

    _ = try await service.enableNotifications(context)

    XCTAssertEqual(permission.requestCount, 1)
    XCTAssertEqual(registrar.registerCount, 1)
    XCTAssertTrue(registrar.registeredAfterPermissionGrant)
  }

  func testEnrollmentAndDelegationBindProfileAndEndpointEpochAndUseKeychain() async throws {
    let keychain = FakeSecureValueStore()
    let gateway = FakePushGateway()
    let attest = FakeAppAttest()
    let service = makeService(keychain: keychain, gateway: gateway, attest: attest)
    let defaultsKey = "zion.push.apns.token"
    UserDefaults.standard.removeObject(forKey: defaultsKey)

    let grant = try await service.enableNotifications(context)

    let enrollment = try XCTUnwrap(gateway.firstBody(path: "/v1/installations"))
    let delegation = try XCTUnwrap(gateway.firstBody(path: "/v1/delegations"))
    XCTAssertEqual(enrollment["app_profile"] as? String, context.appProfileID)
    XCTAssertEqual(enrollment["endpoint_epoch"] as? Int, 1)
    XCTAssertEqual(delegation["endpoint_epoch"] as? Int, 1)
    XCTAssertEqual(delegation["relay_pubkey"] as? String, context.relayPubkey)
    XCTAssertEqual(grant.appProfileID, context.appProfileID)
    XCTAssertEqual(grant.endpointEpoch, 1)
    XCTAssertNotNil(keychain.data(for: "zion.push.installation.buzz-ios-sandbox"))
    XCTAssertNil(UserDefaults.standard.data(forKey: defaultsKey))
    XCTAssertEqual(attest.attestationHashes.count, 1)
    XCTAssertEqual(attest.assertionHashes.count, 1)
  }

  func testTokenRotationIncrementsEpochAndIssuesNewGrant() async throws {
    let registrar = FakeRemoteNotificationRegistrar(
      tokens: [Data([0x01, 0x02]), Data([0x03, 0x04])]
    )
    let gateway = FakePushGateway()
    let service = makeService(registrar: registrar, gateway: gateway)

    let first = try await service.enableNotifications(context)
    let second = try await service.enableNotifications(context)

    XCTAssertEqual(first.endpointEpoch, 1)
    XCTAssertEqual(second.endpointEpoch, 2)
    XCTAssertNotEqual(first.value, second.value)
    let rotation = try XCTUnwrap(gateway.firstBody(path: "/v1/installations/endpoint"))
    XCTAssertEqual(rotation["endpoint_epoch"] as? Int, 1)
    XCTAssertEqual(rotation["new_endpoint_epoch"] as? Int, 2)
    XCTAssertEqual(rotation["endpoint"] as? String, "0304")
  }

  func testForegroundPolicySuppressesAnyNonGenericRemoteBody() {
    XCTAssertTrue(
      AppDelegate.shouldPresentForegroundNotification(body: "Zion needs attention")
    )
    XCTAssertFalse(
      AppDelegate.shouldPresentForegroundNotification(body: "Approve payroll for Alice")
    )
  }

  private var context: PushEnrollmentContext {
    PushEnrollmentContext(
      gatewayOrigin: URL(string: "https://push.example")!,
      relayPubkey: String(repeating: "a", count: 64),
      appProfileID: "buzz-ios-sandbox",
      expiresAt: Date(timeIntervalSince1970: 1_776_000_000)
    )
  }

  private func makeService(
    permission suppliedPermission: FakeNotificationPermission? = nil,
    registrar suppliedRegistrar: FakeRemoteNotificationRegistrar? = nil,
    keychain: FakeSecureValueStore = FakeSecureValueStore(),
    gateway: FakePushGateway = FakePushGateway(),
    attest: FakeAppAttest = FakeAppAttest()
  ) -> PushEnrollmentService {
    let permission =
      suppliedPermission
      ?? FakeNotificationPermission(status: .authorized, grants: true)
    let registrar =
      suppliedRegistrar
      ?? FakeRemoteNotificationRegistrar(tokens: [Data([0x01, 0x02])])
    registrar.permission = permission
    return PushEnrollmentService(
      permission: permission,
      registrar: registrar,
      appAttest: attest,
      gateway: gateway,
      keychain: keychain,
      now: { Date(timeIntervalSince1970: 1_775_000_000) }
    )
  }
}

@MainActor
private final class FakeNotificationPermission: NotificationPermissionProviding {
  var status: UNAuthorizationStatus
  let grants: Bool
  var requestCount = 0

  init(status: UNAuthorizationStatus, grants: Bool) {
    self.status = status
    self.grants = grants
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    status
  }

  func requestAuthorization() async throws -> Bool {
    requestCount += 1
    if grants { status = .authorized }
    return grants
  }
}

@MainActor
private final class FakeRemoteNotificationRegistrar: RemoteNotificationRegistering {
  var tokens: [Data]
  weak var permission: FakeNotificationPermission?
  var registerCount = 0
  var registeredAfterPermissionGrant = false

  init(tokens: [Data]) {
    self.tokens = tokens
  }

  func registerForRemoteNotifications() async throws -> Data {
    registerCount += 1
    registeredAfterPermissionGrant = permission?.status == .authorized
    guard !tokens.isEmpty else { throw PushEnrollmentError.notReady }
    return tokens.removeFirst()
  }
}

private final class FakeSecureValueStore: SecureValueStoring {
  private var values: [String: Data] = [:]

  func data(for key: String) -> Data? {
    values[key]
  }

  func set(_ data: Data, for key: String) throws {
    values[key] = data
  }

  func remove(_ key: String) throws {
    values.removeValue(forKey: key)
  }
}

private final class FakeAppAttest: AppAttestProviding {
  var isSupported = true
  var attestationHashes: [Data] = []
  var assertionHashes: [Data] = []

  func generateKey() async throws -> String {
    Data(repeating: 0x11, count: 32).base64EncodedString()
  }

  func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
    attestationHashes.append(clientDataHash)
    return Data([0xA1])
  }

  func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
    assertionHashes.append(clientDataHash)
    return Data([0xA2])
  }
}

private final class FakePushGateway: PushGatewayRequesting {
  private(set) var requests: [(path: String, body: [String: Any])] = []
  private var challengeNumber = 0
  private var grantNumber = 0

  func post(
    gatewayOrigin: URL,
    path: String,
    body: [String: Any]
  ) async throws -> [String: Any] {
    requests.append((path, body))
    switch path {
    case "/v1/installations/challenges":
      challengeNumber += 1
      return [
        "challenge_id": "00000000-0000-4000-8000-\(String(format: "%012d", challengeNumber))",
        "challenge": String(repeating: "A", count: 43),
        "expires_at": 1_775_000_300,
      ]
    case "/v1/installations":
      return [
        "installation_handle": "10000000-0000-4000-8000-000000000001",
        "endpoint_epoch": 1,
        "expires_at": 1_776_000_000,
      ]
    case "/v1/installations/endpoint":
      return ["status": "rotated"]
    case "/v1/delegations":
      grantNumber += 1
      return ["endpoint_grant": "grant-\(grantNumber)"]
    case "/v1/delegations/revoke":
      return ["status": "revoked"]
    default:
      throw PushEnrollmentError.gateway("unexpected_path")
    }
  }

  func firstBody(path: String) -> [String: Any]? {
    requests.first(where: { $0.path == path })?.body
  }
}
