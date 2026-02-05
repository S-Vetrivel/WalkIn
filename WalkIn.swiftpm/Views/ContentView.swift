import SwiftUI

struct ContentView: View {
    @StateObject var nav = NavigationManager()
    @State private var navPath: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 25) {
                Text("WalkIn")
                    .font(.system(.largeTitle, design: .rounded)).bold()
                
                // Button 1: Start Recording
                NavigationLink(value: AppRoute.activeRecording) {
                    MenuButton(title: "Start New Path", icon: "plus.circle.fill", color: .blue)
                }
                
                // Button 2: View History
                NavigationLink(value: AppRoute.pathHistory) {
                    MenuButton(title: "Saved Paths", icon: "clock.fill", color: .orange)
                }
                
                Spacer()
            }
            .padding()
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .activeRecording:
                    RecordingView(nav: nav)
                case .pathHistory:
                    HistoryView(nav: nav)
                case .settings:
                    Text("Settings View")
                }
            }
        }
    }
}

// Reusable Button Component
struct MenuButton: View {
    let title: String; let icon: String; let color: Color
    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title).bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(12)
    }
}
