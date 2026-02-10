import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var nav: NavigationManager
    @EnvironmentObject var router: WalkInRouter
    
    @State private var showingSaveAlert = false
    @State private var mapName = ""
    
    @State private var showInstructions = true
    
    func saveMap() {
        let name = mapName.isEmpty ? "Untitled Map" : mapName
        _ = MapStorageService.shared.saveMap(
            name: name,
            nodes: nav.path,
            totalSteps: nav.steps,
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
            // LAYER 1: CAMERA FEED
            if let session = nav.visionService.captureSession {
                CameraPreview(session: session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("Starting Camera...")
                    .foregroundColor(.white)
            }
            
            // LAYER 2: DASHBOARD UI
            VStack(spacing: 15) {
                Spacer().frame(height: 50)
                
                // MARK: - 👁️ OCR TEXT BOX
                // Shows Room Numbers, Exit Signs, Text
                HStack {
                    Image(systemName: "text.viewfinder")
                        .font(.title2)
                        .foregroundColor(.cyan)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("READING TEXT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Text(detectedText)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .id("TEXT-" + detectedText) // Triggers animation
                    }
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // MARK: - 🧠 OBJECT DETECTION BOX
                // Shows "Door", "Monitor", "Chair"
                HStack {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DETECTING OBJECT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                        
                        Text(detectedObject)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .id("OBJ-" + detectedObject)
                    }
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal)
                
                Spacer()
                
                // MARK: - 🗺️ REAL-TIME MAP (Minimap)
                if !nav.path.isEmpty {
                    PathVisualizer(path: nav.path) // Use the new component
                        .frame(height: 200)
                        .padding(.horizontal)
                        .transition(.opacity)
                }
                
                // MARK: - SENSOR DASHBOARD (Bottom)
                VStack(spacing: 25) {
                    // Activity Pill
                    Text(nav.activityStatus)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(nav.activityStatus.contains("Walking") ? Color.green : Color.gray.opacity(0.3))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                        .animation(.spring(), value: nav.activityStatus)
                    
                    // Large Steps
                    VStack(spacing: 0) {
                        Text("\(nav.steps)")
                            .font(.system(size: 70, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 5)
                        Text("STEPS TAKEN")
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Stats Row
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
                .padding(.bottom, 10)
                
                // STOP BUTTON
                Button(action: {
                    nav.stopTracking()
                    showingSaveAlert = true
                }) {
                    Text("FINISH PATH")
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
                         nav.startTracking()
                    }
                } message: {
                    Text("Name your journey to save it.")
                }
            }
            
            // LAYER 3: INSTRUCTIONS OVERLAY
            if showInstructions {
                Color.black.opacity(0.8).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "map.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Start Mapping")
                        .font(.title)
                        .bold()
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InstructionRow(icon: "figure.walk", text: "Walk steadily. The app counts steps.")
                        InstructionRow(icon: "dot.radiowaves.left.and.right", text: "Scan rooms slowly to detect objects.")
                        InstructionRow(icon: "text.viewfinder", text: "Point at signs to read room numbers.")
                    }
                    .padding()
                    
                    Button("I'm Ready") {
                        withAnimation {
                            showInstructions = false
                            nav.startTracking()
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
        }
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
