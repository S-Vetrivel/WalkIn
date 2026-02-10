import SwiftUI

struct ContentView: View {
    // 1. Listen to the Shared Router
    @EnvironmentObject var router: WalkInRouter
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 2. Switch screens based on the Router's state
            switch router.currentRoute {
            case .home:
                HomeView()
                    .transition(.opacity)
                
            case .recording:
                RecordingView()
                    .transition(.opacity)
                
            case .history:
                Text("History View (Placeholder)")
                    .foregroundColor(.white)
                    .onTapGesture { router.goHome() }
                
            case .mapLibrary:
                MapLibraryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: router.currentRoute)
        .preferredColorScheme(.dark)
    }
}
