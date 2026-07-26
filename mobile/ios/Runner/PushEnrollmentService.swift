import CryptoKit
import DeviceCheck
import Foundation
import UIKit
import UserNotifications

enum PushEnrollmentError: Error, Equatable {
  case unsupported
  case denied
  case notReady
  case invalidResponse
  case gateway(String)
}

enum PushNotificationStatus: String {
  case unsupported
  case notDetermined = "not_determined"
  case denied
  case authorized
  case provisional
  case ephemeral
}

struct PushEnrollmentContext: Equatable {
  let gatewayOrigin: URL
  let relayPubkey: String
  let appProfileID: String
  let expiresAt: Date
}

struct PushEndpointGrant: Codable, Equatable {
  let value: String
  let appProfileID: String
  let endpointEpoch: Int
  let generation: Int
  let expiresAt: Date
}

protocol NotificationPermissionProviding: AnyObject {
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization() async throws -> Bool
}

protocol RemoteNotificationRegistering: AnyObject {
  func registerForRemoteNotifications() async throws -> Data
}

protocol AppAttestProviding: AnyObject {
  var isSupported: Bool { get }
  func generateKey() async throws -> String
  func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
  func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

protocol PushGatewayRequesting: AnyObject {
  func post(
    gatewayOrigin: URL,
    path: String,
    body: [String: Any]
  ) async throws -> [String: Any]
}

@MainActor
final class PushEnrollmentService {
  private struct InstallationRecord: Codable {
    var keyID: String
    var handle: String
    var appProfileID: String
    var endpointHex: String
    var endpointEpoch: Int
    var expiresAt: Date
  }

  private struct GrantRecord: Codable {
    let gatewayOrigin: String
    let relayPubkey: String
    let grant: PushEndpointGrant
  }

  private struct Challenge {
    let id: String
    let value: String
  }

  private let permission: NotificationPermissionProviding
  private let registrar: RemoteNotificationRegistering
  private let appAttest: AppAttestProviding
  private let gateway: PushGatewayRequesting
  private let keychain: SecureValueStoring
  private let now: () -> Date
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    permission: NotificationPermissionProviding,
    registrar: RemoteNotificationRegistering,
    appAttest: AppAttestProviding,
    gateway: PushGatewayRequesting,
    keychain: SecureValueStoring,
    now: @escaping () -> Date = Date.init
  ) {
    self.permission = permission
    self.registrar = registrar
    self.appAttest = appAttest
    self.gateway = gateway
    self.keychain = keychain
    self.now = now
    encoder.dateEncodingStrategy = .secondsSince1970
    decoder.dateDecodingStrategy = .secondsSince1970
  }

  func notificationStatus() async -> PushNotificationStatus {
    guard appAttest.isSupported else { return .unsupported }
    return Self.mapStatus(await permission.authorizationStatus())
  }

  func enableNotifications(_ context: PushEnrollmentContext) async throws -> PushEndpointGrant {
    guard appAttest.isSupported else { throw PushEnrollmentError.unsupported }
    var status = await permission.authorizationStatus()
    if status == .notDetermined {
      guard try await permission.requestAuthorization() else {
        throw PushEnrollmentError.denied
      }
      status = await permission.authorizationStatus()
    }
    guard Self.isAuthorized(status) else { throw PushEnrollmentError.denied }

    let token = try await registrar.registerForRemoteNotifications()
    let endpointHex = token.map { String(format: "%02x", $0) }.joined()
    guard !endpointHex.isEmpty else { throw PushEnrollmentError.notReady }

    var installation = try loadInstallation(profile: context.appProfileID)
    if installation == nil {
      installation = try await enroll(context: context, endpointHex: endpointHex)
    } else if installation?.endpointHex != endpointHex {
      installation = try await rotateEndpoint(
        installation: installation!,
        context: context,
        endpointHex: endpointHex
      )
    }
    guard let installation else { throw PushEnrollmentError.notReady }
    return try await delegate(installation: installation, context: context)
  }

  func currentEndpointGrant(_ context: PushEnrollmentContext) -> PushEndpointGrant? {
    guard
      let data = keychain.data(for: grantKey(context)),
      let record = try? decoder.decode(GrantRecord.self, from: data),
      record.gatewayOrigin == context.gatewayOrigin.absoluteString,
      record.relayPubkey == context.relayPubkey,
      record.grant.appProfileID == context.appProfileID,
      record.grant.expiresAt > now()
    else {
      return nil
    }
    return record.grant
  }

  func revokeEndpoint(_ context: PushEnrollmentContext) async throws {
    guard
      let installation = try loadInstallation(profile: context.appProfileID),
      let grant = currentEndpointGrant(context)
    else {
      try keychain.remove(grantKey(context))
      return
    }
    let challenge = try await fetchChallenge(context.gatewayOrigin)
    let transcript = try Self.revokeDelegationTranscript(
      context: context,
      challenge: challenge,
      installation: installation,
      generation: grant.generation
    )
    let assertion = try await appAttest.generateAssertion(
      installation.keyID,
      clientDataHash: Self.sha256(transcript)
    )
    _ = try await gateway.post(
      gatewayOrigin: context.gatewayOrigin,
      path: "/v1/delegations/revoke",
      body: [
        "v": 1,
        "challenge_id": challenge.id,
        "challenge": challenge.value,
        "installation_handle": installation.handle,
        "relay_pubkey": context.relayPubkey,
        "generation": grant.generation,
        "assertion": assertion.base64EncodedString(),
      ]
    )
    try keychain.remove(grantKey(context))
  }

  private func enroll(
    context: PushEnrollmentContext,
    endpointHex: String
  ) async throws -> InstallationRecord {
    let keyID: String
    let keyIDStorageKey = appAttestKey(context.appProfileID)
    if
      let stored = keychain.data(for: keyIDStorageKey),
      let decoded = String(data: stored, encoding: .utf8)
    {
      keyID = decoded
    } else {
      keyID = try await appAttest.generateKey()
      try keychain.set(Data(keyID.utf8), for: keyIDStorageKey)
    }

    let challenge = try await fetchChallenge(context.gatewayOrigin)
    let expiresAt = Int(context.expiresAt.timeIntervalSince1970)
    let transcript = try Self.enrollmentTranscript(
      context: context,
      challenge: challenge,
      keyID: keyID,
      endpointHex: endpointHex,
      endpointEpoch: 1,
      expiresAt: expiresAt
    )
    let attestation = try await appAttest.attestKey(
      keyID,
      clientDataHash: Self.sha256(transcript)
    )
    let response = try await gateway.post(
      gatewayOrigin: context.gatewayOrigin,
      path: "/v1/installations",
      body: [
        "v": 1,
        "challenge_id": challenge.id,
        "challenge": challenge.value,
        "key_id": keyID,
        "attestation": attestation.base64EncodedString(),
        "app_profile": context.appProfileID,
        "endpoint": endpointHex,
        "endpoint_epoch": 1,
        "expires_at": expiresAt,
      ]
    )
    guard
      let handle = response["installation_handle"] as? String,
      let epoch = response["endpoint_epoch"] as? Int,
      let responseExpiry = response["expires_at"] as? Int,
      epoch == 1
    else {
      throw PushEnrollmentError.invalidResponse
    }
    let record = InstallationRecord(
      keyID: keyID,
      handle: handle,
      appProfileID: context.appProfileID,
      endpointHex: endpointHex,
      endpointEpoch: epoch,
      expiresAt: Date(timeIntervalSince1970: TimeInterval(responseExpiry))
    )
    try storeInstallation(record)
    return record
  }

  private func rotateEndpoint(
    installation: InstallationRecord,
    context: PushEnrollmentContext,
    endpointHex: String
  ) async throws -> InstallationRecord {
    let challenge = try await fetchChallenge(context.gatewayOrigin)
    let newEpoch = installation.endpointEpoch + 1
    let transcript = try Self.rotationTranscript(
      context: context,
      challenge: challenge,
      installation: installation,
      newEpoch: newEpoch,
      endpointHex: endpointHex
    )
    let assertion = try await appAttest.generateAssertion(
      installation.keyID,
      clientDataHash: Self.sha256(transcript)
    )
    _ = try await gateway.post(
      gatewayOrigin: context.gatewayOrigin,
      path: "/v1/installations/endpoint",
      body: [
        "v": 1,
        "challenge_id": challenge.id,
        "challenge": challenge.value,
        "installation_handle": installation.handle,
        "endpoint_epoch": installation.endpointEpoch,
        "new_endpoint_epoch": newEpoch,
        "endpoint": endpointHex,
        "assertion": assertion.base64EncodedString(),
      ]
    )
    var replacement = installation
    replacement.endpointHex = endpointHex
    replacement.endpointEpoch = newEpoch
    try storeInstallation(replacement)
    return replacement
  }

  private func delegate(
    installation: InstallationRecord,
    context: PushEnrollmentContext
  ) async throws -> PushEndpointGrant {
    let generation = (loadGrantRecord(context)?.grant.generation ?? 0) + 1
    let challenge = try await fetchChallenge(context.gatewayOrigin)
    let notBefore = Int(now().timeIntervalSince1970)
    let expiresAt = min(
      Int(context.expiresAt.timeIntervalSince1970),
      Int(installation.expiresAt.timeIntervalSince1970)
    )
    let transcript = try Self.delegationTranscript(
      context: context,
      challenge: challenge,
      installation: installation,
      generation: generation,
      notBefore: notBefore,
      expiresAt: expiresAt
    )
    let assertion = try await appAttest.generateAssertion(
      installation.keyID,
      clientDataHash: Self.sha256(transcript)
    )
    let response = try await gateway.post(
      gatewayOrigin: context.gatewayOrigin,
      path: "/v1/delegations",
      body: [
        "v": 1,
        "challenge_id": challenge.id,
        "challenge": challenge.value,
        "installation_handle": installation.handle,
        "endpoint_epoch": installation.endpointEpoch,
        "generation": generation,
        "relay_pubkey": context.relayPubkey,
        "not_before": notBefore,
        "expires_at": expiresAt,
        "assertion": assertion.base64EncodedString(),
      ]
    )
    guard let value = response["endpoint_grant"] as? String, !value.isEmpty else {
      throw PushEnrollmentError.invalidResponse
    }
    let grant = PushEndpointGrant(
      value: value,
      appProfileID: context.appProfileID,
      endpointEpoch: installation.endpointEpoch,
      generation: generation,
      expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))
    )
    let record = GrantRecord(
      gatewayOrigin: context.gatewayOrigin.absoluteString,
      relayPubkey: context.relayPubkey,
      grant: grant
    )
    try keychain.set(try encoder.encode(record), for: grantKey(context))
    return grant
  }

  private func fetchChallenge(_ gatewayOrigin: URL) async throws -> Challenge {
    let response = try await gateway.post(
      gatewayOrigin: gatewayOrigin,
      path: "/v1/installations/challenges",
      body: ["v": 1]
    )
    guard
      let id = response["challenge_id"] as? String,
      let value = response["challenge"] as? String,
      !id.isEmpty,
      !value.isEmpty
    else {
      throw PushEnrollmentError.invalidResponse
    }
    return Challenge(id: id, value: value)
  }

  private func loadInstallation(profile: String) throws -> InstallationRecord? {
    guard let data = keychain.data(for: installationKey(profile)) else { return nil }
    return try decoder.decode(InstallationRecord.self, from: data)
  }

  private func storeInstallation(_ record: InstallationRecord) throws {
    try keychain.set(try encoder.encode(record), for: installationKey(record.appProfileID))
  }

  private func loadGrantRecord(_ context: PushEnrollmentContext) -> GrantRecord? {
    guard let data = keychain.data(for: grantKey(context)) else { return nil }
    return try? decoder.decode(GrantRecord.self, from: data)
  }

  private func installationKey(_ profile: String) -> String {
    "zion.push.installation.\(profile)"
  }

  private func appAttestKey(_ profile: String) -> String {
    "zion.push.appattest.\(profile)"
  }

  private func grantKey(_ context: PushEnrollmentContext) -> String {
    "zion.push.grant.\(context.appProfileID).\(context.gatewayOrigin.host ?? "unknown").\(context.relayPubkey)"
  }

  private static func mapStatus(_ status: UNAuthorizationStatus) -> PushNotificationStatus {
    switch status {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .authorized: .authorized
    case .provisional: .provisional
    case .ephemeral: .ephemeral
    @unknown default: .unsupported
    }
  }

  private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
    status == .authorized || status == .provisional || status == .ephemeral
  }

  private static func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  private static func enrollmentTranscript(
    context: PushEnrollmentContext,
    challenge: Challenge,
    keyID: String,
    endpointHex: String,
    endpointEpoch: Int,
    expiresAt: Int
  ) throws -> Data {
    try transcript(
      domain: "buzz.push.enroll.v1",
      fields: [
        ("v", "1"),
        ("audience", quoted(route(context.gatewayOrigin, "/v1/installations"))),
        ("challenge_id", quoted(challenge.id)),
        ("challenge", quoted(challenge.value)),
        ("key_id", quoted(keyID)),
        ("app_profile", quoted(context.appProfileID)),
        ("endpoint", quoted(endpointHex)),
        ("endpoint_epoch", "\(endpointEpoch)"),
        ("expires_at", "\(expiresAt)"),
      ]
    )
  }

  private static func delegationTranscript(
    context: PushEnrollmentContext,
    challenge: Challenge,
    installation: InstallationRecord,
    generation: Int,
    notBefore: Int,
    expiresAt: Int
  ) throws -> Data {
    try transcript(
      domain: "buzz.push.delegate.v1",
      fields: [
        ("v", "1"),
        ("audience", quoted(route(context.gatewayOrigin, "/v1/delegations"))),
        ("challenge_id", quoted(challenge.id)),
        ("challenge", quoted(challenge.value)),
        ("installation_handle", quoted(installation.handle)),
        ("endpoint_epoch", "\(installation.endpointEpoch)"),
        ("generation", "\(generation)"),
        ("relay_pubkey", quoted(context.relayPubkey)),
        ("not_before", "\(notBefore)"),
        ("expires_at", "\(expiresAt)"),
      ]
    )
  }

  private static func rotationTranscript(
    context: PushEnrollmentContext,
    challenge: Challenge,
    installation: InstallationRecord,
    newEpoch: Int,
    endpointHex: String
  ) throws -> Data {
    try transcript(
      domain: "buzz.push.rotate-endpoint.v1",
      fields: [
        ("v", "1"),
        (
          "audience",
          quoted(route(context.gatewayOrigin, "/v1/installations/endpoint"))
        ),
        ("challenge_id", quoted(challenge.id)),
        ("challenge", quoted(challenge.value)),
        ("installation_handle", quoted(installation.handle)),
        ("endpoint_epoch", "\(installation.endpointEpoch)"),
        ("new_endpoint_epoch", "\(newEpoch)"),
        ("endpoint", quoted(endpointHex)),
      ]
    )
  }

  private static func revokeDelegationTranscript(
    context: PushEnrollmentContext,
    challenge: Challenge,
    installation: InstallationRecord,
    generation: Int
  ) throws -> Data {
    try transcript(
      domain: "buzz.push.revoke-delegation.v1",
      fields: [
        (
          "v",
          "1"
        ),
        (
          "audience",
          quoted(route(context.gatewayOrigin, "/v1/delegations/revoke"))
        ),
        ("challenge_id", quoted(challenge.id)),
        ("challenge", quoted(challenge.value)),
        ("installation_handle", quoted(installation.handle)),
        ("relay_pubkey", quoted(context.relayPubkey)),
        ("generation", "\(generation)"),
      ]
    )
  }

  private static func transcript(
    domain: String,
    fields: [(String, String)]
  ) throws -> Data {
    let object = fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",")
    guard let data = "\(domain)\n{\(object)}".data(using: .utf8) else {
      throw PushEnrollmentError.invalidResponse
    }
    return data
  }

  private static func quoted(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [value])
    guard
      let encoded = String(data: data, encoding: .utf8),
      encoded.count >= 2
    else {
      throw PushEnrollmentError.invalidResponse
    }
    return String(encoded.dropFirst().dropLast())
  }

  private static func route(_ origin: URL, _ path: String) -> String {
    origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
  }
}

@MainActor
final class SystemNotificationPermissionProvider: NotificationPermissionProviding {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await center.notificationSettings().authorizationStatus
  }

  func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .badge, .sound])
  }
}

@MainActor
final class ApplicationRemoteNotificationRegistrar: RemoteNotificationRegistering {
  var onTokenChanged: (() -> Void)?
  private var latestToken: Data?
  private var continuation: CheckedContinuation<Data, Error>?

  func registerForRemoteNotifications() async throws -> Data {
    if let latestToken { return latestToken }
    guard continuation == nil else { throw PushEnrollmentError.notReady }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  func didRegister(token: Data) {
    let changed = latestToken != nil && latestToken != token
    latestToken = token
    continuation?.resume(returning: token)
    continuation = nil
    if changed { onTokenChanged?() }
  }

  func didFail(_ error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

final class SystemAppAttestProvider: AppAttestProviding {
  private let service = DCAppAttestService.shared

  var isSupported: Bool { service.isSupported }

  func generateKey() async throws -> String {
    try await service.generateKey()
  }

  func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
    try await service.attestKey(keyID, clientDataHash: clientDataHash)
  }

  func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
    try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
  }
}

final class URLSessionPushGateway: PushGatewayRequesting {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func post(
    gatewayOrigin: URL,
    path: String,
    body: [String: Any]
  ) async throws -> [String: Any] {
    guard let url = URL(string: path, relativeTo: gatewayOrigin) else {
      throw PushEnrollmentError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    guard request.httpBody?.count ?? 0 <= 8192 else {
      throw PushEnrollmentError.invalidResponse
    }
    let (data, response) = try await session.data(for: request)
    guard
      let httpResponse = response as? HTTPURLResponse,
      let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw PushEnrollmentError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw PushEnrollmentError.gateway(decoded["error"] as? String ?? "invalid_response")
    }
    return decoded
  }
}
