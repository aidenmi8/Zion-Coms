import SwiftUI

@main
struct ZionWatchApp: App {
  @StateObject private var store: WatchInboxStore

  init() {
    _store = StateObject(
      wrappedValue: WatchInboxStore(
        cache: WatchInboxCache(),
        transport: WatchConnectivityClient()
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      FocusedQueueView(store: store)
        .preferredColorScheme(.dark)
    }
  }
}
