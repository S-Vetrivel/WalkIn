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
    @Published var guidanceMessage: String = "Wait for AR initialization..."
    
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
    func startNavigation(with savedPath: [PathNode], mapId: UUID? = nil) {
        guard mode == .idle else { return }
        print("🚀 Starting Navigation Session...")
        
        // Load path
        // We start in 'startingNavigation' to allow AR to stabilize
        self.mode = .startingNavigation 
        self.path = savedPath
        self.targetNodeIndex = 0
        
        // Don't reset path, but reset other sensors
        self.checkpointsCrossed = 0
        self.startTime = Date()
        
        // Load World Map if available
        if let mapId = mapId,
           let worldMap = MapStorageService.shared.loadWorldMap(mapId: mapId) {
            arManager.loadWorldMap(worldMap)
            print("🌍 Loaded ARWorldMap for stable navigation")
        } else {
            print("⚠️ No ARWorldMap found for this path. Navigation accuracy may be low.")
            self.guidanceMessage = "⚠️ No Map Data. Accuracy Limited."
        }
        
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
    func stopTracking() {
        print("🛑 Stopping Tracking...")
        isTracking = false
        arManager.pauseSession()
        visionService.stopSession()
        activityManager.stopActivityUpdates()
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        pollingTask?.cancel()
        
        mode = .idle
        guidanceMessage = "Stopped."
    }
    
    private func processARFrame(_ frame: ARFrame?) {
        guard let frame = frame, isTracking else { return }
        
        // Get Position from ARKit
        let transform = frame.camera.transform
        let position = transform.columns.3
        
        // Update 3D position for UI/SceneKit
        // With ARWorldMap, we trust the raw AR coordinates match our saved map
        self.position3D = (position.x, position.y, position.z)
        
        // Track current floor level (every 3m = 1 floor)
        self.currentFloor = Int(round(position.y / 3.0))
        
        // HANDLE MODES
        switch mode {
        case .recording:
            checkForCheckpointCrossing(currentPos: position)
            
            // Capture Obstacle Points (Throttle to 5Hz to avoid memory explosion - every 0.2s)
            if frame.timestamp - lastPointCaptureTime > 0.2 {
                if let rawPoints = frame.rawFeaturePoints?.points {
                    self.obstaclePoints.append(contentsOf: rawPoints)
                }
                lastPointCaptureTime = frame.timestamp
            }
            
            // Feed Vision Service (OCR)
            if let pixelBuffer = frame.capturedImage as CVPixelBuffer? {
                visionService.process(pixelBuffer: pixelBuffer)
            }
            
        case .startingNavigation, .navigating:
            // Check tracking state to ensure we are relocalized
            if let frame = arManager.currentFrame, frame.camera.trackingState == .normal {
                // If we were waiting for relocalization, we can switch to navigating
                if mode == .startingNavigation {
                     self.mode = .navigating
                     self.guidanceMessage = "✅ Location Found"
                }
            } else {
                self.guidanceMessage = "Move device slowly to recognize surroundings..."
            }
            
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
    
    // MARK: - Point-to-Point Navigation
    var destinationNodeId: UUID?
    
    func setDestination(nodeId: UUID) {
        // Validation: Ensure node exists
        guard let index = path.firstIndex(where: { $0.id == nodeId }) else {
            print("❌ Destination node not found in path")
            return
        }
        
        self.destinationNodeId = nodeId
        print("📍 Destination set to Node \(index) (ID: \(nodeId))")
        
        // Recalculate target to point towards this destination
        // We need to find the closes node to current position, then determine direction
        if let currentTransform = arManager.cameraTransform {
            let currentPos = SIMD3<Float>(currentTransform.columns.3.x, currentTransform.columns.3.y, currentTransform.columns.3.z)
            // Find closest node index
            var closestDist = Float.greatestFiniteMagnitude
            var closestIndex = 0
            
            for (i, node) in path.enumerated() {
                let d = distance(currentPos, node.position)
                if d < closestDist {
                    closestDist = d
                    closestIndex = i
                }
            }
            
            // Determine direction
            if index > closestIndex {
                // Moving forward
                self.targetNodeIndex = closestIndex + 1
            } else {
                // Moving backward
                self.targetNodeIndex = max(closestIndex - 1, 0)
            }
        }
    }

    // MARK: - Navigation Guidance
    private func updateNavigationGuidance(currentPos: simd_float4) {
        guard !path.isEmpty else { return }
        
        // Standard behavior: Go to next index.
        // But if we have a destination, we need to ensure targetNodeIndex is moving TOWARDS it.
        
        var nextStepIndex = targetNodeIndex
        
        // If destination set, ensure we are moving towards it
        if let destId = destinationNodeId, let _ = path.firstIndex(where: { $0.id == destId }) {
            // Basic logic: We are at 'targetNodeIndex' (which is our immediate goal).
            // But we should check if our current target is actually leading us to the destination?
            // Yes, because setDestination sets targetNodeIndex.
            // And update loop below increments/decrements it.
            // So nextStepIndex IS targetNodeIndex.
            nextStepIndex = targetNodeIndex
        }
        
        // Ensure bounds
        nextStepIndex = max(0, min(nextStepIndex, path.count - 1))
        
        let targetNode = path[nextStepIndex]
        let currentPos3 = SIMD3<Float>(currentPos.x, currentPos.y, currentPos.z)
        let targetPos3 = targetNode.position
        
        distanceToNextNode = distance(currentPos3, targetPos3)
        
        // Floor guidance
        let targetFloor = Int(round(targetNode.position.y / 3.0))
        if targetFloor > currentFloor {
            self.guidanceMessage = "⬆️ Go UP to Level \(targetFloor)"
        } else if targetFloor < currentFloor {
            self.guidanceMessage = "⬇️ Go DOWN to Level \(targetFloor)"
        } else {
             // Only show generic message if no floor change
             if let destId = destinationNodeId, let destIndex = path.firstIndex(where: { $0.id == destId }) {
                 if nextStepIndex == destIndex {
                     self.guidanceMessage = "🏁 Arriving..."
                 } else {
                     self.guidanceMessage = "Go to \(path[destIndex].aiLabel ?? "Destination")"
                 }
             } else {
                 self.guidanceMessage = "Follow Path"
             }
        }
        
        // If close enough, move to next target
        if distanceToNextNode < 1.0 { // 1 meter threshold
            print("🎯 Reached Node \(nextStepIndex)!")
            
            if let destId = destinationNodeId, let destIndex = path.firstIndex(where: { $0.id == destId }) {
                // Check if we arrived
                if nextStepIndex == destIndex {
                     self.guidanceMessage = "🎉 Arrived at Destination!"
                     self.destinationNodeId = nil // Clear destination
                     return
                }
                
                // Advance towards destination
                if destIndex > nextStepIndex {
                    targetNodeIndex += 1
                } else {
                    targetNodeIndex -= 1
                }
            } else {
                // Default: Forward only
                if targetNodeIndex < path.count - 1 {
                    targetNodeIndex += 1
                } else {
                    self.guidanceMessage = "🏁 Path Complete"
                }
            }
        }
    }

    // MARK: - Data Recording
    private func recordMovement(at transform: simd_float4x4, imageFilename: String? = nil) {
        // Optimized: We do NOT capture images for every normal node.
        // imageFilename is passed in ONLY if this is a special node (Landmark etc)
        
        let node = PathNode(
            timestamp: Date(),
            stepCount: self.checkpointsCrossed,
            heading: self.heading,
            floorLevel: self.floorLevel,
            transform: transform, // Use exact AR transform
            image: imageFilename, // Only save image if explicitly provided
            aiLabel: nil, // Will be updated if OCR runs
            detectedObject: nil
        )
        self.path.append(node)
        print("📍 Added PathNode at: \(node.position) with image: \(imageFilename ?? "None")")
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
            
            // Drop a new node every 0.8 meters
            if dist > 0.8 {
                checkpointsCrossed += 1
                recordMovement(at: arManager.cameraTransform ?? matrix_identity_float4x4)
                print("✅ Checkpoint dropped. Dist: \(dist)")
            }
        }
    }
    
    func placeAnchor() {
        // Manual anchor placement - Treat as a landmark?
        // For now, simple record
        recordMovement(at: arManager.cameraTransform ?? matrix_identity_float4x4)
    }
    
    func addNamedPoint(name: String) {
        // Capture current transform
        guard let transform = arManager.cameraTransform else { return }
        
        // Capture Image specifically for this landmark
        var imageFilename: String? = nil
        
        if let frame = arManager.currentFrame {
            let pixelBuffer = frame.capturedImage
            // We need to do this synchronously or semi-synch to get the filename
            // But saving is async. We can save the node with the known filename now.
            
            let nodeId = UUID() // Generate a UUID for the image file
            
            // Generate filename deterministically or use the UUID
            // We'll trust ImageLocalizationService to return the path, but we need it now.
            // Let's modify ImageLocalizationService to just take the ID and return the path?
            // Or just do the saving in background.
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                 let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                 // Save synchronously-ish (it returns the string)
                 imageFilename = ImageLocalizationService.shared.saveNodeImage(uiImage, nodeId: nodeId)
            }
            
            // Now create the node
             let node = PathNode(
                timestamp: Date(),
                stepCount: self.checkpointsCrossed,
                heading: self.heading,
                floorLevel: self.floorLevel,
                transform: transform,
                image: imageFilename, 
                aiLabel: name,
                detectedObject: nil,
                isManualLandmark: true,
                source: .manual
            )
            
            self.path.append(node)
            print("📍 Added Manual Landmark: \(name) at \(node.position)")
        }
    }
    
    // MARK: - Saving
    func saveCurrentPath() -> Bool {
        print("💾 saveCurrentPath() called. Path count: \(path.count)")
        guard !path.isEmpty else {
            print("⚠️ Path is empty, nothing to save.")
            return false 
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let defaultName = "Path \(formatter.string(from: Date()))"
        
        // Capture Environmental Data
        let currentWalls = arManager.session.currentFrame?.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .map { WallGeometry(anchor: $0) }
            
        // Capture Mapping Status
        var status = "Limited"
        if let frame = arManager.session.currentFrame {
            switch frame.worldMappingStatus {
            case .mapped: status = "Mapped"
            case .extending: status = "Extending"
            case .limited: status = "Limited"
            case .notAvailable: status = "Not Available"
            @unknown default: status = "Unknown"
            }
        }
        print("🌍 Mapping Status: \(status)")
        
        let savedMap = MapStorageService.shared.saveMap(
            name: defaultName,
            nodes: path,
            totalSteps: checkpointsCrossed,
            startTime: startTime ?? Date(),
            walls: currentWalls,
            obstaclePoints: self.obstaclePoints,
            mappingStatus: status
        )
        print("✅ Saved Map ID: \(savedMap.id)")
        
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
    
    // MARK: - Smart OCR Prompting
    struct PendingLandmark {
        let text: String
        let timestamp: Date
        let transform: simd_float4x4
        let snapshot: UIImage?
    }
    
    @Published var pendingLandmark: PendingLandmark?
    private var pendingLandmarkTimer: Timer?
    
    // Priority Keywords for filtering noise
    private let landmarkLexicon: [String] = [
        "Room", "Office", "Lab", "Library", "Kitchen", "Exit",
        "Conference", "Meeting", "Hall", "Lobby", "Reception",
        "Stairs", "Elevator", "Restroom", "Toilet", "Cafeteria"
    ]
    
    // MARK: - AI Context Methods (The Brain)
    func updateAIContext(text: String?, object: String?) {
        guard isTracking else { return }
        
        // 🔥 FORCE UI REFRESH
        self.objectWillChange.send()
        
        if let t = text {
            self.currentAIReadout = "TEXT: \(t)"
            print("✅ UI Updated with TEXT: \(t)")
            
            // 🔍 Intelligent Filtering
            // 1. Check if we already have a pending prompt (don't spam)
            if pendingLandmark == nil && mode == .recording {
                // 2. Check if text contains any keyword
                // Case insensitive check
                let lowerText = t.lowercased()
                let match = landmarkLexicon.first { lowerText.contains($0.lowercased()) }
                
                if let _ = match {
                    // 3. Trigger Pending Landmark
                    if let currentTransform = arManager.cameraTransform {
                        // Capture snapshot now
                        var snapshot: UIImage?
                        if let pixelBuffer = arManager.currentFrame?.capturedImage {
                             let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                             let context = CIContext()
                             if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                                 snapshot = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                             }
                        }
                        
                        let pending = PendingLandmark(
                            text: t,
                            timestamp: Date(),
                            transform: currentTransform,
                            snapshot: snapshot
                        )
                        
                        Task { @MainActor in
                            self.pendingLandmark = pending
                            
                            // Auto-dismiss after 8 seconds
                            self.pendingLandmarkTimer?.invalidate()
                            self.pendingLandmarkTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                                Task { @MainActor in self?.pendingLandmark = nil }
                            }
                        }
                    }
                }
            }
        }
        
        if let o = object {
             // Optional: Use object to trigger landmarks too?
             // For now just display
             if text == nil { // Priority to text
                 self.currentAIReadout = "OBJECT: \(o)"
             }
        }
    }
    
    func confirmPendingLandmark() {
        guard let pending = pendingLandmark else { return }
        
        // Save as landmark
        // Capture image from potential snapshot
        var imageFilename: String? = nil
        let nodeId = UUID()
        
        if let snapshot = pending.snapshot {
             imageFilename = ImageLocalizationService.shared.saveNodeImage(snapshot, nodeId: nodeId)
        }
        
        let node = PathNode(
            timestamp: Date(),
            stepCount: self.checkpointsCrossed,
            heading: self.heading,
            floorLevel: self.floorLevel,
            transform: pending.transform,
            image: imageFilename,
            aiLabel: pending.text,
            detectedObject: nil,
            isManualLandmark: true,
            source: .aiPrompt
        )
        
        self.path.append(node)
        print("✅ Auto-Landmark Confirmed: \(pending.text)")
        
        // Clear
        self.pendingLandmark = nil
        self.pendingLandmarkTimer?.invalidate()
    }
    
    func dismissPendingLandmark() {
        self.pendingLandmark = nil
        self.pendingLandmarkTimer?.invalidate()
    }
}
