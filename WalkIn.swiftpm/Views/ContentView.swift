import SwiftUI

struct ContentView: View {
    @StateObject var navManager = NavigationManager()
    @StateObject var router = Router()
    
    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .activeRecording:
                        RecordingView(nav: navManager)
                    case .pathHistory:
                        HistoryView(nav: navManager)
                    case .settings:
                        Text("Settings")
                    }
                }
        }
        .environmentObject(router) // Shared so any view can trigger navigation
    }
}
