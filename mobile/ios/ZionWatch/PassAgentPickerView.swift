import SwiftUI

struct PassAgentPickerView: View {
  @ObservedObject var store: WatchInboxStore
  let item: WatchWireInboxItem

  var body: some View {
    List(item.eligibleAgents, id: \.pubkey) { agent in
      NavigationLink {
        ActionConfirmationView(
          store: store,
          item: item,
          action: .pass,
          targetAgent: agent
        )
      } label: {
        HStack {
          Circle()
            .fill(
              agent.availability == .online
                ? WatchTheme.approve
                : WatchTheme.secondaryText
            )
            .frame(width: 7, height: 7)
          Text(agent.displayName)
            .lineLimit(1)
        }
      }
      .accessibilityLabel(
        "\(agent.displayName), \(agent.availability.rawValue)"
      )
    }
    .navigationTitle("Pass to")
  }
}
