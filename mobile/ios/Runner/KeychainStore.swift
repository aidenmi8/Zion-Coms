import Foundation
import Security

protocol SecureValueStoring {
  func data(for key: String) -> Data?
  func set(_ data: Data, for key: String) throws
  func remove(_ key: String) throws
}

enum KeychainStoreError: Error {
  case unexpectedStatus(OSStatus)
}

final class KeychainStore: SecureValueStoring {
  private let service: String

  init(service: String = Bundle.main.bundleIdentifier ?? "com.buzz.buzzMobile") {
    self.service = service
  }

  func data(for key: String) -> Data? {
    var query = baseQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { return nil }
    return result as? Data
  }

  func set(_ data: Data, for key: String) throws {
    let query = baseQuery(key)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(updateStatus)
    }
    var inserted = query
    inserted.merge(attributes) { _, new in new }
    let addStatus = SecItemAdd(inserted as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(addStatus)
    }
  }

  func remove(_ key: String) throws {
    let status = SecItemDelete(baseQuery(key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }
}
