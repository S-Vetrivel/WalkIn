import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var nav: NavigationManager
    @EnvironmentObject var router: WalkInRouter
    
    var body: some View {
        ZStack {
            // LAYER 1: CAMERA
            if let session = nav.visionService.captureSession {
                CameraPreview(session: session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("Starting Camera...")
                    .foregroundColor(.white)
            }
            
            // LAYER 2: DASHBOARD
            VStack(spacing: 20) {
                Spacer().frame(height: 40)
                
                // MARK: - AI EYE HUD (Debug Mode)
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.yellow)
                    
                    // Direct binding to the text
                    Text(nav.currentAIReadout)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white) // High contrast white text
                        .lineLimit(1)
                        // Animation to highlight changes
                        .id(nav.currentAIReadout)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                // Red border helps you see if the box is even rendering
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // MARK: - SENSORS
                VStack(spacing: 25) {
                    // Activity Status
                    Text(nav.activityStatus)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(nav.activityStatus.contains("Walking") ? Color.green : Color.gray.opacity(0.3))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                    
                    // Steps
                    VStack(spacing: 0) {
                        Text("\(nav.steps)")
                            .font(.system(size: 70, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("STEPS")
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Telemetry Row
                    HStack(spacing: 40) {
                        DataWidget(icon: "arrow.up.and.down", value: String(format: "%.1f m", nav.floorLevel), label: "ELEV")
                            .foregroundColor(.green)
                        DataWidget(icon: "safari", value: "\(Int(nav.heading))°", label: "HEAD")
                            .foregroundColor(.red)
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                
                Spacer()
                
                // STOP BUTTON
                Button(action: {
                    print(nav.generateJourneySummary())
                    nav.stopTracking()
                    router.navigate(to: .home)
                }) {
                    Text("FINISH PATH")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                }
                .padding(30)
            }
        }
        .onAppear {
            nav.startTracking()
        }
    }
}

struct DataWidget: View {
    let icon: String, value: String, label: String
    var body: some View {
        VStack {
            Image(systemName: icon).font(.title3)
            Text(value).font(.title3).bold().monospaced()
            Text(label).font(.caption2).opacity(0.7)
        }
    }
}
