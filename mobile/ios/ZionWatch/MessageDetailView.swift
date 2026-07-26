import SwiftUI

struct MessageDetailView: View {
  @ObservedObject var store: WatchInboxStore
  let item: WatchWireInboxItem

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Text(item.senderLabel)
          .font(.headline)
        if let channel = item.channelLabel {
          Text(channel)
            .font(.caption)
            .foregroundStyle(WatchTheme.secondaryText)
        }
        Text(item.body)
          .font(.body)
        if item.isTruncated {
          Text("Continues on iPhone…")
            .font(.caption)
            .foregroundStyle(WatchTheme.secondaryText)
        }
        Button {
          store.openOnPhone(itemID: item.itemID)
        } label: {
          Label("Open on iPhone", systemImage: "iphone")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.violet)
        .disabled(
          store.isReadOnly || store.actionState(for: item.itemID).isInFlight
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
    .navigationTitle("Message")
  }
}
