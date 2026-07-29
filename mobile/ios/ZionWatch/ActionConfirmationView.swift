import SwiftUI

struct ActionConfirmationView: View {
  @ObservedObject var store: WatchInboxStore
  let item: WatchWireInboxItem
  let action: WatchWireAction
  let targetAgent: WatchWireAgentSummary?

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(action.tint)
        Text(title)
          .font(.headline)
          .multilineTextAlignment(.center)
        Text(item.body)
          .font(.caption)
          .foregroundStyle(WatchTheme.secondaryText)
          .multilineTextAlignment(.center)
          .lineLimit(4)
        Button {
          if action == .pass, let targetAgent {
            store.requestPass(
              itemID: item.itemID,
              targetAgentPubkey: targetAgent.pubkey
            )
          } else {
            store.requestConfirmation(itemID: item.itemID, action: action)
          }
          store.confirmAction()
        } label: {
          Text("Confirm \(action.label)")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(action.tint)
        .disabled(store.actionState(for: item.itemID).isInFlight)
        .accessibilityLabel("Confirm \(title)")
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Confirm")
  }

  private var title: String {
    switch action {
    case .approve:
      "Approve \(item.senderLabel)'s request?"
    case .deny:
      "Stop this request?"
    case .pass:
      "Pass to \(targetAgent?.displayName ?? "agent")?"
    case .openOnPhone:
      "Open on iPhone?"
    }
  }

  private var icon: String {
    switch action {
    case .approve: "checkmark"
    case .deny: "xmark"
    case .pass: "arrow.right"
    case .openOnPhone: "iphone"
    }
  }
}
