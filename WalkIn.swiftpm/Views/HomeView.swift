import SwiftUI

struct HomeView: View {
    @EnvironmentObject var router: WalkInRouter
    @EnvironmentObject var navManager: NavigationManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("WalkIn")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
            
            Text("Indoor Navigation Engine")
                .foregroundColor(.gray)
            
            Spacer()
            
            Button(action: {
                // COMMAND: Switch to Recording
                navManager.startRecording()
                router.navigate(to: .recording)
            }) {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start New Path")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
            }

            .padding(.horizontal)
            
            Button(action: {
                router.navigate(to: .mapLibrary)
            }) {
                HStack {
                    Image(systemName: "folder")
                    Text("View Saved Maps")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}
