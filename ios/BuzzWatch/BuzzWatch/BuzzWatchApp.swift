import SwiftUI

@main
struct BuzzWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.primary)
                .task { model.start() }
                .onChange(of: phase) { _, now in
                    if now == .active { model.resume() } else { model.active = false }
                }
        }
    }
}
