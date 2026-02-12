import SwiftUI
import UIKit // For UIImage

struct RecordingView: View {
    @EnvironmentObject var nav: NavigationManager
    @EnvironmentObject var router: WalkInRouter
    
    @State private var showInstructions = true
    @State private var show3DView = false // Added view toggle state
    @State private var showLandmarkInput = false
    @State private var landmarkName = ""
    
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
                                    Scene3DView(path: nav.path, checkpoints: [], walls: nil, worldMap: nil, userPosition: nav.position3D)
                                } else {
                                    PathVisualizer(path: nav.path, checkpoints: [], userPosition: nav.position3D)
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
                    HStack(spacing: 30) {
                        DataWidget(icon: "arrow.up.and.down", value: String(format: "%.1f m", nav.floorLevel), label: "ALT")
                            .foregroundColor(.green)
                        
                        DataWidget(icon: "layers.fill", value: "L\(nav.currentFloor)", label: "FLOOR")
                            .foregroundColor(.blue)
                        
                        DataWidget(icon: "mappin.and.ellipse", value: "\(nav.path.count)", label: "NODES")
                            .foregroundColor(.orange)
                    }
                    
                    // Manual Drop Button (Optional)
                    if nav.mode == .navigating {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Next Checkpoint: \(nav.targetNodeIndex)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(String(format: "Distance: %.1fm", nav.distanceToNextNode))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            
                            // Alignment Badge
                            if nav.alignmentScore > 0.6 {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Synced")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(16)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                    } else {
                        Button(action: {
                            landmarkName = ""
                            showLandmarkInput = true
                        }) {
                            Label("Mark Point", systemImage: "flag.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(Color.yellow.opacity(0.8))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                // STOP BUTTON
                Button(action: {
                    if nav.mode == .navigating {
                        nav.stopTracking()
                        router.navigate(to: .home)
                    } else {
                        // Recording: Save immediately
                        nav.stopTracking()
                        _ = nav.saveCurrentPath()
                        router.navigate(to: .home)
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
            }
            
            // LAYER 2.5: GUIDANCE OVERLAY
            if nav.mode != .idle && !showInstructions {
                VStack {
                    HStack {
                        Spacer()
                        Text(nav.guidanceMessage)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(nav.alignmentScore > 0.6 ? Color.green.opacity(0.8) : Color.black.opacity(0.6))
                            .cornerRadius(20)
                        Spacer()
                    }
                    .padding(.top, 110) // Below HUD
                    
                    // NEW: 'MATCH THIS VIEW' GUIDANCE
                    if nav.alignmentScore < 0.5 && nav.mode != .idle {
                        VStack(spacing: 8) {
                            Text("MATCH THIS VIEW")
                                .font(.caption2)
                                .fontWeight(.black)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .cornerRadius(4)
                            
                            if let nodeId = nav.bestMatchNodeId,
                               let node = nav.path.first(where: { $0.id == nodeId }),
                               let filename = node.image,
                               let uiImage = ImageLocalizationService.shared.loadUIImage(filename: filename) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 5)
                            } else {
                                // Default icon if no node image yet
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .frame(width: 120, height: 120)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            Text("Move camera to align with the saved snapshot")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                }
            }
            
            // LAYER 3: INSTRUCTIONS & ALERTS OVERLAY
            
            // PENDING LANDMARK CONFIRMATION CARD
            if let pending = nav.pendingLandmark {
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Text("LANDMARK DETECTED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(pending.text)
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        HStack(spacing: 20) {
                            Button(action: {
                                withAnimation {
                                    nav.dismissPendingLandmark()
                                }
                            }) {
                                Text("Dismiss")
                                    .fontWeight(.semibold)
                                    .frame(minWidth: 100)
                                    .padding()
                                    .background(Color.gray.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                withAnimation {
                                    nav.confirmPendingLandmark()
                                }
                            }) {
                                Text("Add Landmark")
                                    .fontWeight(.bold)
                                    .frame(minWidth: 120)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(24)
                    .shadow(radius: 20)
                    .padding(30)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(100) // Ensure it sits on top
            }
            
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
            
            // LAYER 4: VISUAL ALIGNMENT UI
            if nav.mode == .startingNavigation {
                Color.black.opacity(0.6).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Visual Alignment")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Point camera at any recorded node to sync.")
                        .foregroundColor(.gray)
                    
                    // Reference Image (Shows closest match or start)
                    let displayNode = nav.path.first(where: { $0.id == nav.bestMatchNodeId }) ?? nav.path.first
                    if let node = displayNode, let imagePath = node.image,
                       let image = ImageLocalizationService.shared.loadUIImage(filename: imagePath) {
                        VStack {
                            Text(nav.bestMatchNodeId != nil ? "Closest Landmark" : "Reference (Start)")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        }
                    }
                    
                    // Match Score Indicator
                    VStack {
                        Text("MATCH SCORE")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        
                        HStack {
                            ProgressView(value: Double(nav.alignmentScore))
                                .progressViewStyle(LinearProgressViewStyle(tint: nav.alignmentScore > 0.6 ? .green : .red))
                                .frame(height: 8)
                            Text(String(format: "%.0f%%", nav.alignmentScore * 100))
                                .font(.headline)
                                .foregroundColor(nav.alignmentScore > 0.6 ? .green : .red)
                                .frame(width: 50)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Controls
                    Button(action: {
                        withAnimation {
                            nav.mode = .navigating // Start!
                        }
                    }) {
                        HStack {
                            if nav.alignmentScore > 0.6 {
                                Image(systemName: "checkmark.circle.fill")
                                Text("START NAVIGATION")
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("FORCE START")
                            }
                        }
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(nav.alignmentScore > 0.6 ? Color.green : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.top)
                    
                    Text("Point camera at the start location until score turns green.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(30)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(30)
                .transition(.scale)
            }
        }
        .alert("Name this location", isPresented: $showLandmarkInput) {
            TextField("e.g. Room 101", text: $landmarkName)
            Button("Cancel", role: .cancel) { }
            Button("Mark") {
                if !landmarkName.isEmpty {
                    nav.addNamedPoint(name: landmarkName)
                }
            }
        } message: {
            Text("Enter a name for this landmark.")
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
    
}
