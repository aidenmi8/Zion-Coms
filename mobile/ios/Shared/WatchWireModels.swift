import Foundation

let watchWireSchemaVersion = 1
let watchWireMaximumItems = 20
let watchWireMaximumBodyScalars = 2_000

enum WatchWireError: Error, Equatable {
  case unsupportedVersion(Int)
  case invalidField(String)
  case tooManyItems
  case bodyTooLong
}

enum WatchWireItemType: String, Codable {
  case approval
  case directMessage
  case mention
}

enum WatchWireAction: String, Codable {
  case approve
  case deny
  case pass
  case openOnPhone
}

enum WatchWireActionOutcome: String, Codable {
  case accepted
  case alreadyResolved
  case rejected
  case retryable
}

enum WatchWireAgentAvailability: String, Codable {
  case online
  case away
}

struct WatchWireAgentSummary: Codable, Equatable {
  let pubkey: String
  let displayName: String
  let availability: WatchWireAgentAvailability
  let sortRank: Int

  func validate() throws {
    guard Self.isLowerHex64(pubkey) else {
      throw WatchWireError.invalidField("agent.pubkey")
    }
    guard
      !displayName.isEmpty,
      displayName.unicodeScalars.count <= 100,
      sortRank >= 0
    else {
      throw WatchWireError.invalidField("agent")
    }
  }

  private static func isLowerHex64(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }
}

struct WatchWireInboxItem: Codable, Equatable {
  let itemID: String
  let type: WatchWireItemType
  let communityID: String
  let channelID: String?
  let title: String
  let senderLabel: String
  let channelLabel: String?
  let body: String
  let createdAt: Date
  let expiresAt: Date?
  let sourceEventID: String
  let isTruncated: Bool
  let allowedActions: [WatchWireAction]
  let eligibleAgents: [WatchWireAgentSummary]

  init(
    itemID: String,
    type: WatchWireItemType,
    communityID: String,
    channelID: String?,
    title: String,
    senderLabel: String,
    channelLabel: String?,
    body: String,
    createdAt: Date,
    expiresAt: Date?,
    sourceEventID: String,
    isTruncated: Bool,
    allowedActions: [WatchWireAction],
    eligibleAgents: [WatchWireAgentSummary]
  ) throws {
    self.itemID = itemID
    self.type = type
    self.communityID = communityID
    self.channelID = channelID
    self.title = title
    self.senderLabel = senderLabel
    self.channelLabel = channelLabel
    self.body = body
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.sourceEventID = sourceEventID
    self.isTruncated = isTruncated
    self.allowedActions = allowedActions
    self.eligibleAgents = eligibleAgents
    try validate()
  }

  func validate() throws {
    guard
      !itemID.isEmpty,
      itemID.utf8.count <= 256,
      !communityID.isEmpty,
      communityID.utf8.count <= 256,
      !title.isEmpty,
      title.unicodeScalars.count <= 200,
      !senderLabel.isEmpty,
      senderLabel.unicodeScalars.count <= 200,
      sourceEventID.utf8.count <= 256,
      eligibleAgents.count <= 20,
      Set(allowedActions).count == allowedActions.count
    else {
      throw WatchWireError.invalidField("item")
    }
    guard body.unicodeScalars.count <= watchWireMaximumBodyScalars else {
      throw WatchWireError.bodyTooLong
    }
    if let channelID, channelID.utf8.count > 256 {
      throw WatchWireError.invalidField("channelID")
    }
    if let channelLabel, channelLabel.unicodeScalars.count > 200 {
      throw WatchWireError.invalidField("channelLabel")
    }
    for agent in eligibleAgents {
      try agent.validate()
    }
  }
}

struct WatchSnapshotEnvelope: Codable, Equatable {
  let schemaVersion: Int
  let communityID: String
  let communityName: String
  let generatedAt: Date
  let items: [WatchWireInboxItem]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "version"
    case communityID
    case communityName
    case generatedAt
    case items
  }

  init(
    schemaVersion: Int = watchWireSchemaVersion,
    communityID: String,
    communityName: String,
    generatedAt: Date,
    items: [WatchWireInboxItem]
  ) throws {
    self.schemaVersion = schemaVersion
    self.communityID = communityID
    self.communityName = communityName
    self.generatedAt = generatedAt
    self.items = items
    try validate()
  }

  func validate() throws {
    guard schemaVersion == watchWireSchemaVersion else {
      throw WatchWireError.unsupportedVersion(schemaVersion)
    }
    guard items.count <= watchWireMaximumItems else {
      throw WatchWireError.tooManyItems
    }
    guard
      communityID.utf8.count <= 256,
      communityName.unicodeScalars.count <= 200
    else {
      throw WatchWireError.invalidField("community")
    }
    for item in items {
      try item.validate()
      guard item.communityID == communityID else {
        throw WatchWireError.invalidField("item.communityID")
      }
    }
  }

  func encoded() throws -> Data {
    try WatchWireCodec.encode(self)
  }

  static func decode(_ data: Data) throws -> WatchSnapshotEnvelope {
    let value = try WatchWireCodec.decode(Self.self, from: data)
    try value.validate()
    return value
  }
}

struct WatchActionRequestEnvelope: Codable, Equatable {
  let schemaVersion: Int
  let actionID: UUID
  let communityID: String
  let itemID: String
  let action: WatchWireAction
  let targetAgentPubkey: String?

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "version"
    case actionID
    case communityID
    case itemID
    case action
    case targetAgentPubkey
  }

  init(
    schemaVersion: Int = watchWireSchemaVersion,
    actionID: UUID,
    communityID: String,
    itemID: String,
    action: WatchWireAction,
    targetAgentPubkey: String?
  ) throws {
    self.schemaVersion = schemaVersion
    self.actionID = actionID
    self.communityID = communityID
    self.itemID = itemID
    self.action = action
    self.targetAgentPubkey = targetAgentPubkey
    try validate()
  }

  func validate() throws {
    guard schemaVersion == watchWireSchemaVersion else {
      throw WatchWireError.unsupportedVersion(schemaVersion)
    }
    guard
      !communityID.isEmpty,
      communityID.utf8.count <= 256,
      !itemID.isEmpty,
      itemID.utf8.count <= 256
    else {
      throw WatchWireError.invalidField("action")
    }
    if action == .pass {
      guard
        let targetAgentPubkey,
        targetAgentPubkey.range(
          of: "^[0-9a-f]{64}$",
          options: .regularExpression
        ) != nil
      else {
        throw WatchWireError.invalidField("targetAgentPubkey")
      }
    } else if targetAgentPubkey != nil {
      throw WatchWireError.invalidField("targetAgentPubkey")
    }
  }

  func encoded() throws -> Data {
    try WatchWireCodec.encode(self)
  }

  static func decode(_ data: Data) throws -> WatchActionRequestEnvelope {
    let value = try WatchWireCodec.decode(Self.self, from: data)
    try value.validate()
    return value
  }
}

struct WatchActionResultEnvelope: Codable, Equatable {
  let schemaVersion: Int
  let actionID: UUID
  let communityID: String
  let itemID: String
  let outcome: WatchWireActionOutcome
  let message: String
  let resolvedAt: Date

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "version"
    case actionID
    case communityID
    case itemID
    case outcome
    case message
    case resolvedAt
  }

  init(
    schemaVersion: Int = watchWireSchemaVersion,
    actionID: UUID,
    communityID: String,
    itemID: String,
    outcome: WatchWireActionOutcome,
    message: String,
    resolvedAt: Date
  ) throws {
    self.schemaVersion = schemaVersion
    self.actionID = actionID
    self.communityID = communityID
    self.itemID = itemID
    self.outcome = outcome
    self.message = message
    self.resolvedAt = resolvedAt
    try validate()
  }

  func validate() throws {
    guard schemaVersion == watchWireSchemaVersion else {
      throw WatchWireError.unsupportedVersion(schemaVersion)
    }
    guard
      !communityID.isEmpty,
      communityID.utf8.count <= 256,
      !itemID.isEmpty,
      itemID.utf8.count <= 256,
      !message.isEmpty,
      message.unicodeScalars.count <= 200
    else {
      throw WatchWireError.invalidField("result")
    }
  }

  func encoded() throws -> Data {
    try WatchWireCodec.encode(self)
  }

  static func decode(_ data: Data) throws -> WatchActionResultEnvelope {
    let value = try WatchWireCodec.decode(Self.self, from: data)
    try value.validate()
    return value
  }
}

enum WatchWireCodec {
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  static func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data
  ) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }
}
