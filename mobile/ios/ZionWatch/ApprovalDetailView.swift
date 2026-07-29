import SwiftUI

struct ApprovalDetailView: View {
  @ObservedObject var store: WatchInboxStore
  let item: WatchWireInboxItem

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Label("Approval", systemImage: "checkmark.shield")
          .font(.caption.weight(.semibold))
          .foregroundStyle(WatchTheme.violet)
        Text(item.body)
          .font(.body)
          .foregroundStyle(WatchTheme.primaryText)
        metadata
        actionStatus
        if !store.isReadOnly {
          actions
        } else {
          Text("Open Zion on iPhone to act on this cached request.")
            .font(.caption)
            .foregroundStyle(WatchTheme.secondaryText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
    .navigationTitle("Review")
  }

  private var metadata: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(item.senderLabel)
      if let channel = item.channelLabel {
        Text(channel)
      }
      Text(item.createdAt, style: .relative)
      if let expiresAt = item.expiresAt {
        Text("Expires \(expiresAt, style: .relative)")
      }
    }
    .font(.caption)
    .foregroundStyle(WatchTheme.secondaryText)
  }

  @ViewBuilder
  private var actionStatus: some View {
    switch store.actionState(for: item.itemID) {
    case .idle:
      EmptyView()
    case .queued:
      Label("Queued for iPhone", systemImage: "clock")
        .foregroundStyle(WatchTheme.secondaryText)
    case .sending:
      ProgressView("Sending")
    case .succeeded(let message):
      Label(message, systemImage: "checkmark.circle.fill")
        .foregroundStyle(WatchTheme.approve)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.circle")
        .foregroundStyle(WatchTheme.deny)
    }
  }

  private var actions: some View {
    VStack(spacing: 8) {
      if item.allowedActions.contains(.approve) {
        confirmationLink(.approve)
      }
      if item.allowedActions.contains(.deny) {
        confirmationLink(.deny)
      }
      if item.allowedActions.contains(.pass), !item.eligibleAgents.isEmpty {
        NavigationLink {
          PassAgentPickerView(store: store, item: item)
        } label: {
          Label("Pass to Agent", systemImage: "arrow.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.violet)
      }
      if item.allowedActions.contains(.openOnPhone) {
        Button {
          store.openOnPhone(itemID: item.itemID)
        } label: {
          Label("Open on iPhone", systemImage: "iphone")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
      }
    }
    .disabled(store.actionState(for: item.itemID).isInFlight)
  }

  private func confirmationLink(_ action: WatchWireAction) -> some View {
    NavigationLink {
      ActionConfirmationView(
        store: store,
        item: item,
        action: action,
        targetAgent: nil
      )
    } label: {
      Text(action.label)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(action.tint)
  }
}
