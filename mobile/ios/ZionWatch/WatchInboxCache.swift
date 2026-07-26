import Foundation

protocol WatchInboxCaching: AnyObject {
  func load() throws -> WatchSnapshotEnvelope?
  func replace(with snapshot: WatchSnapshotEnvelope) throws
}

final class WatchInboxCache: WatchInboxCaching {
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

  func load() throws -> WatchSnapshotEnvelope? {
    guard fileManager.fileExists(atPath: snapshotURL.path) else { return nil }
    return try WatchSnapshotEnvelope.decode(Data(contentsOf: snapshotURL))
  }

  func replace(with snapshot: WatchSnapshotEnvelope) throws {
    try snapshot.validate()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ]
    )
    try snapshot.encoded().write(to: snapshotURL, options: .atomic)
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: snapshotURL.path
    )
  }

  private var snapshotURL: URL {
    directory.appendingPathComponent("snapshot.json")
  }
}
