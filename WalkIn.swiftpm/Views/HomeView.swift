import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 25) {
            Text("WalkIn")
                .font(.system(.largeTitle, design: .rounded)).bold()
            
            // Fixed: Removed the editor placeholder content block
            NavigationLink(value: AppRoute.activeRecording) {
                MenuButton(title: "Start New Path", icon: "plus.circle.fill", color: .blue)
            }
            
            NavigationLink(value: AppRoute.pathHistory) {
                MenuButton(title: "Saved Paths", icon: "clock.fill", color: .orange)
            }
            
            Spacer()
        }
        .padding()
    }
}
