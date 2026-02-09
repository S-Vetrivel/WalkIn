import SwiftUI


@MainActor
class WalkInRouter: ObservableObject {
    // The Active Screen (Starts at Home)
    @Published var currentRoute: AppRoute = .home
    
    // Function to change screens with animation
    func navigate(to route: AppRoute) {
        withAnimation(.easeInOut) {
            currentRoute = route
        }
    }
    
    // Helper to return to start
    func goHome() {
        navigate(to: .home)
    }
}
