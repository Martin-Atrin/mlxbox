import SwiftUI

@main
struct MLXBoxApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
