import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var nav: NavigationManager
    @EnvironmentObject var router: WalkInRouter
    
    @State private var showingSaveAlert = false
    @State private var mapName = ""
    @State private var showInstructions = true
    @State private var show3DView = false // Added view toggle state
    
    func saveMap() {
        let name = mapName.isEmpty ? "Untitled Map" : mapName
        _ = MapStorageService.shared.saveMap(
            name: name,
            nodes: nav.path,
            totalSteps: nav.checkpointsCrossed,
            startTime: nav.startTime ?? Date() // We need to track start time in NavManager
        )
    }
    
    // Separate State for smoother animations
    var detectedText: String {
        if nav.currentAIReadout.starts(with: "TEXT:") {
            return String(nav.currentAIReadout.dropFirst(6))
        }
        return "..."
    }
    
    var detectedObject: String {
        if nav.currentAIReadout.starts(with: "OBJ:") {
            return String(nav.currentAIReadout.dropFirst(5))
        }
        return "Scanning..."
    }
    
    var body: some View {
        ZStack {
            // LAYER 1: AR WORLD (Main View)
            // LAYER 1: AR WORLD (Main View)
            ARViewContainer(path: nav.path, targetNodeIndex: nav.targetNodeIndex, mode: nav.mode)
                .edgesIgnoringSafeArea(.all)
            
            // LAYER 2: DASHBOARD UI
            VStack(spacing: 15) {

                
                // MARK: - TOP HUD
                HStack(alignment: .top) {
                    // LEFT: OCR/AI Status
                    VStack(alignment: .leading, spacing: 10) {
                        if !detectedText.isEmpty && detectedText != "..." {
                            InfoPill(icon: "text.viewfinder", color: .cyan, title: "TEXT", text: detectedText)
                        }
                        
                        if !detectedObject.isEmpty && detectedObject != "Scanning..." {
                            InfoPill(icon: "cube.transparent", color: .yellow, title: "OBJECT", text: detectedObject)
                        }
                    }
                    
                    Spacer()
                    
                    // RIGHT: Mini Map
                    if !nav.path.isEmpty {
                        VStack(spacing: 8) {
                            Group {
                                if show3DView {
                                    Scene3DView(path: nav.path, checkpoints: [])
                                } else {
                                    PathVisualizer(path: nav.path, checkpoints: [])
                                }
                            }
                            .frame(width: 140, height: 180)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 1))
                            
                            Button(action: { withAnimation { show3DView.toggle() } }) {
                                Text(show3DView ? "SWITCH TO 2D" : "SWITCH TO 3D")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // MARK: - SENSOR DASHBOARD (Bottom)
                VStack(spacing: 20) {
                    
                    // AR Status
                    Text(nav.arManager.statusMessage)
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    
                    // Large Checkpoint Counter
                    if nav.mode == .navigating {
                        VStack(spacing: 0) {
                            Text(String(format: "%.1f m", nav.distanceToNextNode))
                                .font(.system(size: 70, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                                .shadow(color: .black.opacity(0.2), radius: 5)
                            Text("DIST TO NEXT")
                                .font(.caption2)
                                .fontWeight(.black)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
                        VStack(spacing: 0) {
                            Text("\(nav.checkpointsCrossed)")
                                .font(.system(size: 70, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 5)
                            Text("ANCHORS PLACED")
                                .font(.caption2)
                                .fontWeight(.black)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    // Stats Row
                    HStack(spacing: 40) {
                        DataWidget(icon: "arrow.up.and.down", value: String(format: "%.1f m", nav.floorLevel), label: "ELEV")
                            .foregroundColor(.green)
                        
                        // Show raw coordinate for debugging?
                        DataWidget(icon: "mappin.and.ellipse", value: "\(nav.path.count)", label: "NODES")
                            .foregroundColor(.orange)
                    }
                    
                    // Manual Drop Button (Optional)
                    Button(action: {
                        nav.placeAnchor()
                    }) {
                        Label("Drop Anchor", systemImage: "mappin")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                // STOP BUTTON
                Button(action: {
                    nav.stopTracking()
                    if nav.mode == .navigating {
                        // Just exit
                        router.navigate(to: .home)
                    } else {
                        // Recording: Prompt to save
                        showingSaveAlert = true
                    }
                }) {
                    Text(nav.mode == .navigating ? "EXIT NAVIGATION" : "FINISH PATH")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(radius: 10)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .alert("Save Map", isPresented: $showingSaveAlert) {
                    TextField("Map Name", text: $mapName)
                    Button("Save") {
                        saveMap()
                        router.navigate(to: .home)
                    }
                    Button("Discard", role: .destructive) {
                        router.navigate(to: .home)
                    }
                    Button("Cancel", role: .cancel) {
                        // Do nothing, resume
                         nav.startRecording()
                    }
                } message: {
                    Text("Name your journey to save it.")
                }
            }
            
            // LAYER 3: INSTRUCTIONS OVERLAY
            if showInstructions && nav.mode == .recording {
                Color.black.opacity(0.8).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "arkit")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Start AR Mapping")
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InstructionRow(icon: "camera.fill", text: "Keep camera pointed forward.")
                        InstructionRow(icon: "figure.walk", text: "Walk slowly to drop 'breadcrumbs'.")
                        InstructionRow(icon: "lightbulb.fill", text: "Ensure good lighting for AR to work.")
                    }
                    .padding()
                    
                    Button("I'm Ready") {
                        withAnimation {
                            showInstructions = false
                            nav.startRecording()
                        }
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(30)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(20)
                .padding(30)
                .transition(.scale)
            }
            
            // LAYER 4: NAVIGATION STARTUP OVERLAY
            if nav.mode == .startingNavigation {
                 Color.black.opacity(0.8).ignoresSafeArea()
                 
                 VStack(spacing: 20) {
                     ProgressView()
                         .progressViewStyle(CircularProgressViewStyle(tint: .white))
                         .scaleEffect(2)
                     
                     Text("Aligning to Start...")
                         .font(.title2)
                         .bold()
                         .foregroundColor(.white)
                     
                     Text("Please stand at the exact starting point of the path and look forward.")
                         .font(.body)
                         .multilineTextAlignment(.center)
                         .foregroundColor(.white.opacity(0.8))
                         .padding(.horizontal)
                     
                     Text("Wait for tracking to stabilize.")
                         .font(.caption)
                         .foregroundColor(.gray)
                 }
                 .padding(40)
                 .background(.ultraThinMaterial)
                 .cornerRadius(20)
            }
        }
    }
}

// Helper View for Info Pills
struct InfoPill: View {
    let icon: String
    let color: Color
    let title: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// Reusable Widget
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
