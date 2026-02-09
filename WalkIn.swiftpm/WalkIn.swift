import SwiftUI

@main
struct WalkInApp: App {
    // 1. Create the Shared Objects ONCE here
    @StateObject private var router = WalkInRouter()
    @StateObject private var navManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 2. Inject them into the environment so all views can see them
                .environmentObject(router)
                .environmentObject(navManager)
        }
    }
}
