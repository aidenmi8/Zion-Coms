import SwiftUI

enum WatchTheme {
  static let background = Color.black
  static let surface = Color.white.opacity(0.08)
  static let violet = Color(red: 0.56, green: 0.38, blue: 1)
  static let approve = Color(red: 0.18, green: 0.78, blue: 0.43)
  static let deny = Color(red: 1, green: 0.28, blue: 0.32)
  static let primaryText = Color.white
  static let secondaryText = Color.white.opacity(0.62)
}

extension WatchWireInboxItem: Identifiable {
  var id: String { itemID }
}

extension WatchWireAction {
  var label: String {
    switch self {
    case .approve: "Approve"
    case .deny: "Deny"
    case .pass: "Pass"
    case .openOnPhone: "Open on iPhone"
    }
  }

  var tint: Color {
    switch self {
    case .approve: WatchTheme.approve
    case .deny: WatchTheme.deny
    case .pass: WatchTheme.violet
    case .openOnPhone: .gray
    }
  }
}
