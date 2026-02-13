import SwiftUI
import ARKit

struct MapLibraryView: View {
    @EnvironmentObject var router: WalkInRouter
    @State private var savedMaps: [SavedMap] = []
    @State private var selectedMap: SavedMap? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { router.goHome() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Text("Saved Maps")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding()
            
            if let map = selectedMap {
                // Detail View
                SavedMapView(map: map, onBack: { selectedMap = nil })
            } else {
                // List View
                if savedMaps.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "map")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No maps saved yet.")
                            .foregroundColor(.gray)
                        Text("Record a path to see it here.")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(savedMaps) { map in
                                Button(action: { selectedMap = map }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(map.name)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Text("\(map.totalSteps) steps • \(map.dateString)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .onAppear {
            print("🗺️ MapLibraryView Appeared")
            loadMaps()
        }
    }
    
    private func loadMaps() {
        savedMaps = MapStorageService.shared.loadMaps()
    }
}

// Detail View for a single map
struct SavedMapView: View {
    @EnvironmentObject var navManager: NavigationManager
    @EnvironmentObject var router: WalkInRouter
    
    let map: SavedMap
    var onBack: () -> Void
    
    @State private var worldMap: ARWorldMap?
    @State private var isLoadingMap = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Text(map.name)
                .font(.title)
                .bold()
                .foregroundColor(.white)
                .padding(.bottom, 8)
            
            // 3D Spatial Map
            if let worldMap = worldMap {
                Scene3DView(path: map.nodes, checkpoints: [], walls: map.walls, worldMap: worldMap)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                // Fallback while loading or if no map
                ZStack {
                    PathVisualizer(path: map.nodes, checkpoints: [])
                    if isLoadingMap {
                        ProgressView("Loading Spatial Map...")
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                    }
                }
                .frame(height: 300)
                .padding(.horizontal)
            }
            
            // ACTION BUTTONS
            Button(action: {
                // START NAVIGATION
                navManager.startNavigation(with: map.nodes, mapId: map.id)
                router.navigate(to: .recording)
            }) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Start Navigation")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Stats
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        StatCard(title: "Steps", value: "\(map.totalSteps)", icon: "figure.walk")
                        StatCard(title: "Duration", value: formatDuration(map.duration), icon: "clock")
                    }
                    .padding(.horizontal)
                    
                    // Points of Interest (Manual Landmarks)
                    let manualLandmarks = map.nodes.filter { $0.isManualLandmark && $0.aiLabel != nil }
                    if !manualLandmarks.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Points of Interest")
                                .font(.headline)
                                .foregroundColor(.yellow)
                                .padding(.horizontal)
                            
                            ForEach(manualLandmarks) { node in
                                Button(action: {
                                    navManager.startNavigation(with: map.nodes, mapId: map.id)
                                    navManager.setDestination(nodeId: node.id)
                                    router.navigate(to: .recording)
                                }) {
                                    HStack {
                                        // Icon based on source
                                        if node.landmarkSource == .aiPrompt {
                                            Image(systemName: "text.viewfinder").foregroundColor(.cyan)
                                        } else {
                                            Image(systemName: "flag.fill").foregroundColor(.yellow)
                                        }
                                        
                                        Text(node.aiLabel ?? "").foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    
                    // Auto-detected Landmarks
                    let landmarks = map.nodes.filter { !$0.isManualLandmark && ($0.aiLabel != nil || $0.detectedObject != nil) }
                    if !landmarks.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Landmarks Found")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ForEach(landmarks) { node in
                                Button(action: {
                                    navManager.startNavigation(with: map.nodes, mapId: map.id)
                                    navManager.setDestination(nodeId: node.id)
                                    router.navigate(to: .recording)
                                }) {
                                    HStack {
                                        if let text = node.aiLabel {
                                            Image(systemName: "text.viewfinder").foregroundColor(.cyan)
                                            Text(text).foregroundColor(.white)
                                        } else if let obj = node.detectedObject {
                                            Image(systemName: "cube.transparent").foregroundColor(.orange)
                                            Text(obj).foregroundColor(.white)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
        }
        .onAppear {
            loadWorldMap()
        }
    }
    
    private func loadWorldMap() {
        isLoadingMap = true
        let mapId = map.id
        Task {
            let loadedMap = MapStorageService.shared.loadWorldMap(mapId: mapId)
            self.worldMap = loadedMap
            self.isLoadingMap = false
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.title3)
                .bold()
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
