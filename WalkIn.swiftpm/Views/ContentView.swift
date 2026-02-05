import SwiftUI

// Define the two main states of the app
enum AppState {
    case home
    case recording
    case history
}

struct ContentView: View {
    // The Single Source of Truth for the whole app
    @StateObject private var navigationManager = NavigationManager()
    @State private var currentRoute: AppState = .home
    
    var body: some View {
        ZStack {
            switch currentRoute {
            case .home:
                // Pass a binding to change routes
                HomeViewWrapper(route: $currentRoute)
                    .environmentObject(navigationManager)
                
            case .recording:
                RecordingViewWrapper(route: $currentRoute)
                    .environmentObject(navigationManager)
                
            case .history:
                // Placeholder for history view
                Text("History View")
                    .foregroundColor(.white)
                    .background(Color.black)
                    .onTapGesture { currentRoute = .home }
            }
        }
        .animation(.easeInOut, value: currentRoute)
        .preferredColorScheme(.dark)
    }
}

// WRAPPERS to connect your existing Views to this Router

struct HomeViewWrapper: View {
    @Binding var route: AppState
    @EnvironmentObject var nav: NavigationManager
    
    var body: some View {
        // We inject the navigation logic into your existing HomeView
        HomeView()
        // NOTE: You need to update HomeView buttons to toggle 'route'
        // For now, this overlay acts as the connector
            .overlay(
                // Invisible tappers if you haven't updated HomeView buttons yet
                VStack {
                    Spacer()
                    HStack {
                        Color.clear
                            .frame(height: 100)
                            .contentShape(Rectangle())
                            .onTapGesture { route = .recording }
                    }
                }
            )
    }
}

struct RecordingViewWrapper: View {
    @Binding var route: AppState
    @EnvironmentObject var nav: NavigationManager
    
    var body: some View {
        RecordingView(nav: nav)
            .overlay(
                // A "Force Quit" button just in case
                Button(action: { route = .home }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                }
                , alignment: .topLeading
            )
    }
}
