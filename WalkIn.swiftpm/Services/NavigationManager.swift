import Foundation
import CoreMotion
import Combine
import ARKit
import simd
import UIKit // For UIImage


@MainActor
class NavigationManager: ObservableObject {
    // MARK: - Publishers
    @Published var checkpointsCrossed: Int = 0
    @Published var heading: Double = 0.0
    @Published var floorLevel: Double = 0.0
    @Published var activityStatus: String = "Ready"
    @Published var currentAIReadout: String = "Scanning..."
    
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
    private var targetFeaturePrint: VNFeaturePrintObservation?
    
    // Checkpoint System
    
    // Checkpoint System
    @Published var checkpoints: [CGPoint] = []
    var currentPosition: CGPoint = .zero
    var lastCheckpointTime: Date = Date()
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
        
        // Prepare Target Feature Print for Alignment (First Node)
        if let firstNode = savedPath.first, let imagePath = firstNode.image {
            if let image = ImageLocalizationService.shared.loadUIImage(filename: imagePath) {
                self.targetFeaturePrint = ImageLocalizationService.shared.generateFeaturePrint(for: image)
                print("🎯 Target Feature Print Loaded")
            }
        }
        
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
        self.lastCheckpointTime = Date()
        self.position3D = (0, 0, 0)
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
        self.position3D = (position.x, position.y, position.z)
        
        // HANDLE MODES
        switch mode {
        case .recording:
            checkForCheckpointCrossing(currentPos: position)
            
        case .startingNavigation:
            // Calculate Alignment Score
            if let currentFrame = arManager.currentFrame, let targetPrint = self.targetFeaturePrint {
                // We throttle this? Vision is somewhat expensive. 
                // But currentFrame updates at 60fps. Maybe run every 10 frames or so?
                // For now, let's try every frame but async might be better. 
                // Since this runs on Main Actor, we shouldn't block.
                // Feature print generation is synchronous in ImageLocalizationService?
                // Yes, it uses VNImageRequestHandler. It might block.
                // Let's offload to background task if possible, BUT we are in a sync function.
                // For a smooth UI, we should probably debounce this.
                // Let's just do it directly for now, optimization later if stutter occurs.
                
                // We need to convert CVPixelBuffer to UIImage for our service
                // Or update service to take CVPixelBuffer (better).
                // Let's convert here for now using our previous logic (or a helper).
                // PERFORMANCE NOTE: This conversion + Vision every frame WILL lag.
                // PROPOSAL: Only run if alignmentScore is < threshold and maybe every 0.1s.
                
                // Quick hack: use a simple counter or timer
                 
                 Task {
                     if let pixelBuffer = currentFrame.capturedImage as CVPixelBuffer? {
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        let context = CIContext()
                        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                            let uiImage = UIImage(cgImage: cgImage)
                            if let currentPrint = ImageLocalizationService.shared.generateFeaturePrint(for: uiImage) {
                                let score = ImageLocalizationService.shared.computeSimilarity(between: currentPrint, and: targetPrint)
                                await MainActor.run {
                                    self.alignmentScore = score
                                }
                            }
                        }
                     }
                 }
            } else {
                // No target image? Auto-score 1.0 (skip alignment)
                self.alignmentScore = 1.0
            }
            
            // Wait for tracking to stabilize AND user to confirm (we remove auto-transition)
            // if arManager.trackingState == .normal { ... }
            // We now wait for manual "Start" button in UI, or auto-start if score is high?
            // User requested "enable the user to navigate from a particular spot".
            // Let's allow manual start but show the score.
            
        case .navigating:
            updateNavigationGuidance(currentPos: position)
            
        case .idle:
            break
        }
    }
    
    // MARK: - Navigation Guidance
    private func updateNavigationGuidance(currentPos: simd_float4) {
        guard !path.isEmpty, targetNodeIndex < path.count else { return }
        
        let targetNode = path[targetNodeIndex]
        let currentPos3 = SIMD3<Float>(currentPos.x, currentPos.y, currentPos.z)
        let targetPos3 = targetNode.position
        
        distanceToNextNode = distance(currentPos3, targetPos3)
        
        // If close enough, move to next target
        if distanceToNextNode < 1.0 { // 1 meter threshold
            targetNodeIndex += 1
            print("🎯 Reached Node \(targetNodeIndex)!")
            // Trigger haptic or sound here
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
            
            // Drop a new node every 1.2 meters
            if dist > 1.2 {
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
        
        _ = MapStorageService.shared.saveMap(
            name: defaultName,
            nodes: path,
            totalSteps: checkpointsCrossed,
            startTime: startTime ?? Date()
        )
        return true
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
