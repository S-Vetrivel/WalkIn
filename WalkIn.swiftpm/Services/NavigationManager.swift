import Foundation
import CoreMotion
import Combine
import ARKit
import simd
import UIKit // For UIImage
@preconcurrency import Vision


@MainActor
class NavigationManager: ObservableObject {
    // MARK: - Publishers
    @Published var checkpointsCrossed: Int = 0
    @Published var heading: Double = 0.0
    @Published var floorLevel: Double = 0.0
    @Published var activityStatus: String = "Ready"
    @Published var currentAIReadout: String = "Scanning..."
    @Published var currentFloor: Int = 0
    
    @Published var path: [PathNode] = []
    @Published var isTracking: Bool = false
    @Published var permissionStatus: String = "Unknown"
    
    // Mode Management
    enum SessionMode {
        case idle, recording, startingNavigation, navigating
    }
    @Published var mode: SessionMode = .idle
    
    // Navigation Targets
    @Published var targetNodeIndex: Int = 0 
    @Published var distanceToNextNode: Float = 0.0
    
    // Alignment
    @Published var alignmentScore: Float = 0.0
    @Published var worldOffset: simd_float4x4 = matrix_identity_float4x4
    @Published var guidanceMessage: String = "Wait for AR initialization..."
    @Published var bestMatchNodeId: UUID? = nil
    
    // Feature Print Cache (Optimization)
    private var nodeFeaturePrints: [UUID: VNFeaturePrintObservation] = [:]
    private var isRelocalizing: Bool = false
    private var lastRelocalizationTime: Date = Date.distantPast
    
    // Checkpoint System
    
    // Checkpoint System
    @Published var checkpoints: [CGPoint] = []
    var currentPosition: CGPoint = .zero
    var lastCheckpointTime: Date = Date()
    
    // Environmental Geometry
    @Published var obstaclePoints: [simd_float3] = []
    private var lastPointCaptureTime: TimeInterval = 0
    let checkpointInterval: TimeInterval = 3.0 // Create checkpoint every 3 seconds
    
    // 3D Position Tracking (for SceneKit visualization)
    var position3D: (x: Float, y: Float, z: Float) = (0, 0, 0)
    let stepLength: Float = 0.7 // meters per checkpoint
    let checkpointDistance: CGFloat = 2.0 // meters
    
    // MARK: - Hardware
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    
    let visionService = VisionService()
    let pathFinderService = PathFinderService() // Initialize Path Finder
    let arManager = ARManager.shared // Use shared ARManager
    private var subscribers = Set<AnyCancellable>()
    
    // Background Polling Task (Used for timed checkpoints if needed, but main drive is AR)
    private var pollingTask: Task<Void, Never>?
    
    @Published var startTime: Date?
    
    // MARK: - Startup
    func startNavigation(with savedPath: [PathNode]) {
        guard mode == .idle else { return }
        print("🚀 Starting Navigation Session...")
        
        // Load path
        // We start in 'startingNavigation' to allow AR to stabilize AND Visual Alignment
        self.mode = .startingNavigation 
        self.path = savedPath
        self.targetNodeIndex = 0
        self.alignmentScore = 0.0
        self.worldOffset = matrix_identity_float4x4
        self.nodeFeaturePrints = [:] // Clear cache
        
        // Prepare Target Feature Print for Alignment (First Node)
        // We now do this dynamically in attemptRelocalization
        
        // Don't reset path, but reset other sensors
        self.checkpointsCrossed = 0
        self.startTime = Date()
        
        checkAuthorizationAndStart()
    }
    
    func startRecording() {
        guard mode == .idle else { return }
        print("🚀 Starting Recording Session...")
        
        // Reset state
        self.mode = .recording
        self.resetSessionData()
        
        checkAuthorizationAndStart()
    }

    private func resetSessionData() {
        self.checkpointsCrossed = 0
        self.checkpoints = []
        self.currentPosition = .zero
        self.path = []
        self.startTime = Date()
        self.startTime = Date()
        self.lastCheckpointTime = Date()
        self.position3D = (0, 0, 0)
        self.obstaclePoints = [] // Clear obstacles
    }
    
    private func checkAuthorizationAndStart() {
        // In iOS Playgrounds, we can just try to start. The OS will prompt.
        self.permissionStatus = "Requesting..."
        self.activateSensors()
    }
    
    private func activateSensors() {
        isTracking = true
        print("🔌 Activating Sensors...")
        visionService.setup(with: self)
        arManager.startSession() // Start AR Session
        
        // Listen to AR Updates
        arManager.$currentFrame
            .receive(on: RunLoop.main)
            .sink { [weak self] frame in
                self?.processARFrame(frame)
                if frame?.camera.trackingState == .normal {
                    self?.guidanceMessage = self?.mode == .navigating ? "Following path..." : "Scan area to start..."
                } else {
                    self?.guidanceMessage = "AR Tracking: \(frame?.camera.trackingState ?? .notAvailable)"
                }
            }
            .store(in: &subscribers)
        
        // 1. Activity Monitor
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] (activity: CMMotionActivity?) in
                guard let self = self, let activity = activity else { return }
                if activity.walking { self.activityStatus = "Walking 🚶" }
                else if activity.running { self.activityStatus = "Running 🏃" }
                else if activity.stationary { self.activityStatus = "Stationary 🧍" }
                else { self.activityStatus = "Moving..." }
            }
        }
        
        // Simplified: We'll use ARKit updates primarily.
        // But we keep a polling task for timed checkpoints if stationary?
        // For now, let's rely on AR movement.
        pollingTask = Task {
            while isTracking {
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
                // Update checkpoints logic if needed
            }
        }
        
        // 3. Compass
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.05
            motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue.main) { [weak self] (motion: CMDeviceMotion?, error: Error?) in
                guard let self = self, let motion = motion else { return }
                let yaw = motion.attitude.yaw
                self.heading = (yaw * 180 / Double.pi + 360).truncatingRemainder(dividingBy: 360)
            }
        }
        
        // 4. Altimeter
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] (data: CMAltitudeData?, error: Error?) in
                guard let self = self, let data = data else { return }
                self.floorLevel = data.relativeAltitude.doubleValue
            }
        } else {
            print("⚠️ Altimeter not available")
        }
    }
    
    // MARK: - AR Processing
    private func processARFrame(_ frame: ARFrame?) {
        guard let frame = frame, isTracking else { return }
        
        // Get Position from ARKit
        let transform = frame.camera.transform
        let position = transform.columns.3
        
        // Update 3D position for UI/SceneKit
        // We want the position in MAP SPACE for the 3D minimap.
        // Current = Offset * Map
        // Map = Inverse(Offset) * Current
        let inverseOffset = worldOffset.inverse
        let mapPos = inverseOffset * position
        self.position3D = (mapPos.x, mapPos.y, mapPos.z)
        
        // Track current floor level (every 3m = 1 floor)
        self.currentFloor = Int(round(mapPos.y / 3.0))
        
        // HANDLE MODES
        switch mode {
        case .recording:
            checkForCheckpointCrossing(currentPos: position)
            
            // Capture Obstacle Points (Throttle to 5Hz to avoid memory explosion - every 0.2s)
            if frame.timestamp - lastPointCaptureTime > 0.2 {
                if let rawPoints = frame.rawFeaturePoints?.points {
                    // Filter points close to user (e.g. within 3m) to avoid capturing distant noise?
                    // For now, capture all valid points.
                    self.obstaclePoints.append(contentsOf: rawPoints)
                }
                lastPointCaptureTime = frame.timestamp
            }
            
        case .startingNavigation, .navigating:
            // Continuous Relocalization
            attemptRelocalization(frame: frame)
            
            if mode == .navigating {
                updateNavigationGuidance(currentPos: position)
                
                // Check Path Safety (Throttled)
                if let pixelBuffer = frame.capturedImage as CVPixelBuffer? {
                    Task {
                        let status = await pathFinderService.process(pixelBuffer: pixelBuffer)
                        if status == .blocked {
                            await MainActor.run {
                                // Trigger Haptic Feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.warning)
                                print("⚠️ Path Blocked!")
                                self.currentAIReadout = "⚠️ OBSTACLE DETECTED"
                            }
                        }
                    }
                }
            }
            
        case .idle:
            break
        }
    }
    
    // MARK: - Relocalization
    private func attemptRelocalization(frame: ARFrame) {
        let now = Date()
        guard !isRelocalizing, now.timeIntervalSince(lastRelocalizationTime) > 1.0 else { return } // Check every 1s
        
        // Candidates:
        // If starting: search entire path (or first 10)
        // If navigating: search +/- 5 nodes from target
        // For simplicity and "jump to any dot" feature: Search ALL nodes? 
        // If path is long, this is expensive. Let's clamp to 20 nearest nodes?
        // Or just search all for now (assuming short paths < 50 nodes).
        
        isRelocalizing = true
        
        // Candidates Optimization: 
        // Only search nodes within 10 meters of current map-projected position.
        // If we are LOST (low alignment), maybe search all? For now, let's try optimization.
        
        let currentMapPos = (worldOffset.inverse * frame.camera.transform.columns.3)
        let currentMapPos3 = SIMD3<Float>(currentMapPos.x, currentMapPos.y, currentMapPos.z)
        
        // Filter candidates (Localized Search)
        // If we have high alignment, we trust our position. If low, we search broader.
        let searchRadius: Float = alignmentScore > 0.4 ? 10.0 : 1000.0 // 1km = all
        
        let candidates = path.filter { node in
            distance(node.position, currentMapPos3) < searchRadius
        }
        
        Task { [weak self] in
            defer { 
                Task { @MainActor in self?.isRelocalizing = false; self?.lastRelocalizationTime = Date() }
            }
            guard let self = self else { return }
            
            // 1. Get Current Feature Print
            guard let pixelBuffer = frame.capturedImage as CVPixelBuffer?,
                  let currentPrint = await self.generateFeaturePrint(from: pixelBuffer) 
            else { return }
            
            // 2. Find Best Match
            var bestMatchNode: PathNode?
            var bestScore: Float = 0.0
            
            // Limit to max 20 checks to prevent frame drops
            // Sort by distance to prioritize closest nodes
            let sortedCandidates = candidates.sorted { 
                distance($0.position, currentMapPos3) < distance($1.position, currentMapPos3)
            }.prefix(20)
            
            for node in sortedCandidates {
                // Get pre-loaded print
                guard let nodePrint = await self.getNodePrint(for: node.id) else { continue }
                
                let score = ImageLocalizationService.shared.computeSimilarity(between: currentPrint, and: nodePrint)
                if score > bestScore {
                    bestScore = score
                    bestMatchNode = node
                }
            }
            
            // 3. Evaluate Match
            await MainActor.run {
                self.alignmentScore = bestScore
                
                if bestScore > 0.65, let match = bestMatchNode {
                    print("✅ RELOCALIZED to Node \(match.stepCount) (Score: \(bestScore))")
                    
                    // Calculate Correction
                    // User is at 'match.position' in the MAP, and at 'frame.position' in CURRENT AR.
                    // We want to shift the MAP so that 'match.position' aligns with 'frame.position'.
                    // MapOffset = CurrentARPos - SavedMapPos
                    
                    let currentARPos = frame.camera.transform.columns.3
                    let savedMapPos = match.transform.columns.3
                    
                    // Construct new offset matrix (Translation + Rotation)
                    // We want: currentARPos = newOffset * savedMapPos
                    // where currentARPos is the FULL 4x4 transform
                    
                    let currentARTransform = frame.camera.transform
                    let savedNodeTransform = match.transform
                    
                    // Simple snap: worldOffset = current * saved.inverse
                    let newOffset = currentARTransform * savedNodeTransform.inverse
                    
                    // Simple snap or smooth?
                    // Let's use a simple smoothing factor to avoid jumping
                    let smoothing: Float = 0.3
                    
                    // Note: Linearly interpolating a 4x4 matrix is mathematically incorrect for rotation,
                    // but for small corrections it works better than snapping.
                    // For a proper implementation, we'd decompose into Quat/Trans and lerp those.
                    // For now, let's use a soft snap: 
                    // currentOffset = lerp(currentOffset, newOffset, 0.3)
                    
                    if self.alignmentScore < 0.5 {
                        // Extreme drift or first match: Snap hard
                        self.worldOffset = newOffset
                    } else {
                        // Regular adjustment: Smooth
                        // self.worldOffset = self.worldOffset.interpolate(to: newOffset, factor: 0.2)
                        // Actually, let's just snap for now to ensure accuracy, but with a high threshold.
                        self.worldOffset = newOffset
                    }
                    
                    self.bestMatchNodeId = match.id
                    self.guidanceMessage = "✅ Position Synced"
                    
                    // If we were starting, jump to navigation
                    if self.mode == .startingNavigation {
                        self.mode = .navigating
                        // Update target index to the one AFTER the match
                        if let matchIdx = self.path.firstIndex(where: { $0.id == match.id }) {
                            self.targetNodeIndex = min(matchIdx + 1, self.path.count - 1)
                        }
                    }
                    
                    // If navigating, maybe jump index if we skipped ahead?
                    if self.mode == .navigating {
                         if let matchIdx = self.path.firstIndex(where: { $0.id == match.id }) {
                             // Only jump forward, never back? Or allow back?
                             // Allow full realignment
                             self.targetNodeIndex = min(matchIdx + 1, self.path.count - 1)
                         }
                    }
                }
            }
        }
    }
    
    // Helper to access Cache safely
    private func getNodePrint(for id: UUID) async -> VNFeaturePrintObservation? {
        // Accessing main actor isolated dictionary
        await MainActor.run { return nodeFeaturePrints[id] }
    }
    
    private func cacheNodePrint(_ id: UUID, print: VNFeaturePrintObservation) async {
        await MainActor.run { nodeFeaturePrints[id] = print }
    }
    
    private func generateFeaturePrint(from pixelBuffer: CVPixelBuffer) async -> VNFeaturePrintObservation? {
        // This runs off-main
        // Use .right to match the orientation of our saved images (which are saved upright from .right sensor data)
        return ImageLocalizationService.shared.generateFeaturePrint(from: pixelBuffer, orientation: .right)
    }
    
    // MARK: - Navigation Guidance
    private func updateNavigationGuidance(currentPos: simd_float4) {
        guard !path.isEmpty, targetNodeIndex < path.count else { return }
        
        let targetNode = path[targetNodeIndex]
        let currentPos3 = SIMD3<Float>(currentPos.x, currentPos.y, currentPos.z)
        let targetPos3 = targetNode.position
        
        distanceToNextNode = distance(currentPos3, targetPos3)
        
        // Floor guidance
        let targetFloor = Int(round(targetNode.position.y / 3.0))
        if targetFloor > currentFloor {
            self.guidanceMessage = "⬆️ Go UP to Level \(targetFloor)"
        } else if targetFloor < currentFloor {
            self.guidanceMessage = "⬇️ Go DOWN to Level \(targetFloor)"
        }
        
        // If close enough, move to next target
        if distanceToNextNode < 1.0 { // 1 meter threshold
            targetNodeIndex += 1
            
            // Clean guidance message after floor change
            if targetFloor == currentFloor {
                self.guidanceMessage = "Following path..."
            }
            
            print("🎯 Reached Node \(targetNodeIndex)!")
        }
    }

    // MARK: - Data Recording
    private func recordMovement(at transform: simd_float4x4) {
        // Capture Image
        var imageFilename: String? = nil
        if let frame = arManager.currentFrame {
            // Convert CVPixelBuffer to UIImage
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                // ARKit images are landscape. We rotate to .right to match portrait UI if needed, 
                // but for feature matching, consistency is key. Let's use .right for easier UI viewing.
                let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                
                // Save using Localization Service
                // We use a temporary UUID for the node to generate the filename
                let nodeId = UUID() 
                // Note: PathNode generates its own UUID, so we should coordinate this. 
                // Let's change PathNode init or just pass this UUID to it? 
                // PathNode.id is var, so we can set it, or init with it.
                // Current PathNode init generates a new UUID. 
                // Let's let PathNode generate it, but we need the filename BEFORE init? 
                // Or we init PathNode, then get its ID, then save image?
                // Let's save image with a new UUID, and pass that filename. 
                // The filename doesn't STRICTLY have to match the Node ID, but it's cleaner.
                // Let's just generate a UUID here for the filename.
                imageFilename = ImageLocalizationService.shared.saveNodeImage(uiImage, nodeId: nodeId)
            }
        }

        let node = PathNode(
            timestamp: Date(),
            stepCount: self.checkpointsCrossed,
            heading: self.heading,
            floorLevel: self.floorLevel,
            transform: transform, // Use exact AR transform
            image: imageFilename, // Save the image path
            aiLabel: nil, // Will be updated if OCR runs
            detectedObject: nil
        )
        self.path.append(node)
        print("📍 Added PathNode at: \(node.position) with image: \(imageFilename ?? "None")")
    }
    
    // Overloaded to support legacy calls if any (though we should migrate them)
    // We'll keep this private and unused if possible, or adapt it
    private func recordMovement() {
        if let transform = arManager.cameraTransform {
            recordMovement(at: transform)
        }
    }
    
    // MARK: - Checkpoint System (AR Version)
    // In AR, checkpoints are just previous nodes. We check distance to the LAST node.
    private func checkForCheckpointCrossing(currentPos: simd_float4) {
        // If path is empty, drop first node
        if path.isEmpty {
            recordMovement(at: arManager.cameraTransform ?? matrix_identity_float4x4)
            return
        }
        
        // Check distance to last recorded node
        if let lastNode = path.last {
            let lastPos = lastNode.position
            let dist = distance(lastPos, SIMD3<Float>(currentPos.x, currentPos.y, currentPos.z))
            
            // Drop a new node every 0.8 meters (Optimized for 3D Blocks)
            if dist > 0.8 {
                checkpointsCrossed += 1
                recordMovement(at: arManager.cameraTransform ?? matrix_identity_float4x4)
                print("✅ Checkpoint dropped. Dist: \(dist)")
            }
        }
    }
    
    func placeAnchor() {
        // Manual anchor placement
        recordMovement()
    }
    
    // MARK: - Saving
    func saveCurrentPath() -> Bool {
        guard !path.isEmpty else { return false }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let defaultName = "Path \(formatter.string(from: Date()))"
        
        // Capture Environmental Data
        let currentWalls = arManager.session.currentFrame?.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .map { WallGeometry(anchor: $0) }
        
        let savedMap = MapStorageService.shared.saveMap(
            name: defaultName,
            nodes: path,
            totalSteps: checkpointsCrossed,
            startTime: startTime ?? Date(),
            walls: currentWalls,
            obstaclePoints: self.obstaclePoints
        )
        
        // Save World Map
        Task {
            do {
                let worldMapData = try await arManager.getWorldMapData()
                try MapStorageService.shared.saveWorldMapData(worldMapData, mapId: savedMap.id)
                print("✅ World Map saved for \(defaultName)")
            } catch {
                print("⚠️ Could not save World Map: \(error)")
            }
        }
        
        return true
    }
    
    // MARK: - Loading (Modified for World Map)
    func startNavigation(with savedPath: [PathNode], mapId: UUID? = nil) {
        guard mode == .idle else { return }
        print("🚀 Starting Navigation Session...")
        
        // Load path
        // We start in 'startingNavigation' to allow AR to stabilize AND Visual Alignment
        self.mode = .startingNavigation 
        self.path = savedPath
        self.targetNodeIndex = 0
        self.alignmentScore = 0.0
        self.worldOffset = matrix_identity_float4x4
        self.nodeFeaturePrints = [:] // Clear cache
        
        // Don't reset path, but reset other sensors
        self.checkpointsCrossed = 0
        self.startTime = Date()
        
        // Load World Map if available
        if let mapId = mapId,
           let worldMap = MapStorageService.shared.loadWorldMap(mapId: mapId) {
            arManager.loadWorldMap(worldMap)
            print("🌍 Loaded ARWorldMap for stable navigation")
        }
        
        checkAuthorizationAndStart()
        
        // Pre-load feature prints for smoother runtime performance
        Task.detached(priority: .userInitiated) {
            await self.preloadFeaturePrints(for: savedPath)
        }
    }
    
    private func preloadFeaturePrints(for nodes: [PathNode]) async {
        print("📥 Pre-loading feature prints for \(nodes.count) nodes...")
        for node in nodes {
            guard let imagePath = node.image else { continue }
            // Check if already cached
            if await self.getNodePrint(for: node.id) != nil { continue }
            
            // Load and cache
            if let uiImage = ImageLocalizationService.shared.loadUIImage(filename: imagePath),
               let print = ImageLocalizationService.shared.generateFeaturePrint(for: uiImage) {
                await self.cacheNodePrint(node.id, print: print)
            }
        }
        print("✅ Feature Print Pre-loading complete.")
    }

    // MARK: - AI Context Methods (The Brain)
        func updateAIContext(text: String?, object: String?) {
            guard isTracking else { return } // Removed !path.isEmpty check which might block updates if path is slow to start
            
            // 🔥 FORCE UI REFRESH
            // This tells SwiftUI: "Hey! Data changed! Redraw the screen NOW!"
            self.objectWillChange.send()
            
            if let t = text {
                self.currentAIReadout = "TEXT: \(t)"
                print("✅ UI Updated with TEXT: \(t)") // Debug Print
            }
            
            if let o = object {
                self.currentAIReadout = "OBJ: \(o)"
                print("✅ UI Updated with OBJ: \(o)") // Debug Print
            }
            
            // Only save to path if we actually have nodes
            if !path.isEmpty {
                var lastNode = path[path.count - 1]
                if let text = text { lastNode.aiLabel = text }
                if let object = object { lastNode.detectedObject = object }
                path[path.count - 1] = lastNode
            }
        }
    func generateJourneySummary() -> String {
        let meaningfulNodes = path.filter { $0.aiLabel != nil || $0.detectedObject != nil }
        var story = "JOURNEY LOG:\n"
        story += "• Started at Elevation 0.0m\n"
        for node in meaningfulNodes {
            if let text = node.aiLabel { story += "• Saw '\(text)' at checkpoint \(node.stepCount)\n" }
            if let obj = node.detectedObject { story += "• Detected \(obj) at checkpoint \(node.stepCount)\n" }
        }
        story += "• Finished with \(checkpointsCrossed) checkpoints crossed."
        return story
    }
    
    // MARK: - Shutdown
    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        mode = .idle
        
        pollingTask?.cancel()
        pollingTask = nil
        subscribers.removeAll() // Stop listening to AR updates
        
        arManager.pauseSession()
        
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        visionService.stopSession()
        
        print("🛑 Session Finished.")
    }
}
