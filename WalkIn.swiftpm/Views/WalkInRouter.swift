import SwiftUI

class Router: ObservableObject {
    @Published var path: [AppRoute] = []
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func goBack() {
        path.removeLast()
    }
    
    func reset() {
        path = []
    }
}
