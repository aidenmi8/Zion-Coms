import SwiftUI

struct FocusedQueueView: View {
  @ObservedObject var store: WatchInboxStore

  var body: some View {
    NavigationStack {
      Group {
        if store.items.isEmpty {
          emptyState
        } else {
          List {
            if store.isShowingCachedData {
              Label("Waiting for iPhone", systemImage: "iphone.slash")
                .font(.caption2)
                .foregroundStyle(WatchTheme.secondaryText)
                .listRowBackground(WatchTheme.background)
            }
            Section {
              ForEach(store.items) { item in
                NavigationLink {
                  destination(for: item)
                } label: {
                  FocusedQueueRow(item: item)
                }
                .listRowBackground(WatchTheme.background)
                .accessibilityLabel(
                  "\(item.title), from \(item.senderLabel), \(item.body)"
                )
              }
            } header: {
              Text("\(store.items.count) needing attention")
                .foregroundStyle(WatchTheme.secondaryText)
            }
          }
          .listStyle(.carousel)
        }
      }
      .navigationTitle(store.communityName.isEmpty ? "Zion" : store.communityName)
      .containerBackground(WatchTheme.background, for: .navigation)
    }
    .tint(WatchTheme.violet)
  }

  @ViewBuilder
  private func destination(for item: WatchWireInboxItem) -> some View {
    if item.type == .approval {
      ApprovalDetailView(store: store, item: item)
    } else {
      MessageDetailView(store: store, item: item)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: store.isShowingCachedData ? "iphone.slash" : "checkmark.circle")
        .font(.title2)
        .foregroundStyle(
          store.isShowingCachedData ? WatchTheme.secondaryText : WatchTheme.approve
        )
      Text(store.isShowingCachedData ? "Waiting for iPhone" : "You're clear")
        .font(.headline)
      Text(
        store.isShowingCachedData
          ? "Open Zion on iPhone to refresh."
          : "Nothing needs attention."
      )
      .font(.caption)
      .foregroundStyle(WatchTheme.secondaryText)
      .multilineTextAlignment(.center)
    }
    .padding()
  }
}

private struct FocusedQueueRow: View {
  let item: WatchWireInboxItem

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(item.type == .approval ? WatchTheme.violet : Color.clear)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(item.type == .approval ? "APPROVAL" : item.senderLabel.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
              item.type == .approval
                ? WatchTheme.violet
                : WatchTheme.secondaryText
            )
          Spacer()
          Text(item.createdAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(WatchTheme.secondaryText)
        }
        Text(item.title)
          .font(.headline)
          .foregroundStyle(WatchTheme.primaryText)
          .lineLimit(1)
        Text(item.body)
          .font(.caption)
          .foregroundStyle(WatchTheme.secondaryText)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }
}
