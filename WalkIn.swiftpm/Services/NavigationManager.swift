import Foundation
import CoreMotion
import Combine

@MainActor
class NavigationManager: ObservableObject {
    // MARK: - Publishers
    @Published var steps: Int = 0
    @Published var heading: Double = 0.0
    @Published var floorLevel: Double = 0.0
    @Published var activityStatus: String = "Stationary"
    @Published var currentAIReadout: String = "Scanning..."
    
    @Published var path: [PathNode] = []
    @Published var isTracking: Bool = false
    @Published var permissionStatus: String = "Unknown"
    
    // MARK: - Hardware
    // These are let constants, so they are safe
    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    
    let visionService = VisionService()
    
    // Background Polling Task
    private var pollingTask: Task<Void, Never>?
    
    @Published var startTime: Date?
    
    // For accelerometer-based step detection (iPad fallback)
    private var lastPeakTime: Date = Date()
    
    // MARK: - Startup
    func startTracking() {
        guard !isTracking else { return }
        print("🚀 Requesting Access...")
        
        // Reset state for new session
        self.steps = 0
        self.path = []
        self.startTime = Date()
        
        checkAuthorizationAndStart()
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
        
        // 1. Activity Monitor
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity = activity else { return }
                if activity.walking { self?.activityStatus = "Walking 🚶" }
                else if activity.running { self?.activityStatus = "Running 🏃" }
                else if activity.stationary { self?.activityStatus = "Stationary 🧍" }
                else { self?.activityStatus = "Moving..." }
            }
        }
        
        // 2. Pedometer (Reverting to queryPedometerData for iPad environment compatibility)
        if CMPedometer.isStepCountingAvailable() {
            let sessionStartTime = Date()
            pollingTask = Task {
                while isTracking {
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000) // Poll every 1s
                    
                    self.pedometer.queryPedometerData(from: sessionStartTime, to: Date()) { [weak self] data, error in
                        guard let data = data, let self = self else { return }
                        let count = data.numberOfSteps.intValue
                        
                        Task { @MainActor in
                            self.updateStepsSafe(count)
                        }
                    }
                }
            }
        } else {
            print("⚠️ Pedometer not available. Using Accelerometer Fallback (iPad mode/Simulator)...")
            // FALLBACK: Manual Step Detection using Accelerometer (For iPad/Simulator)
            if motionManager.isAccelerometerAvailable {
                motionManager.accelerometerUpdateInterval = 0.1
                let threshold: Double = 1.2 // g-force threshold for a step
                
                motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                    guard let data = data else { return }
                    
                    // Calculate magnitude: sqrt(x^2 + y^2 + z^2)
                    let magnitude = sqrt(pow(data.acceleration.x, 2) + pow(data.acceleration.y, 2) + pow(data.acceleration.z, 2))
                    
                    // Simple peak detection with 0.4s cooldown (debounce)
                    if magnitude > threshold {
                        Task { @MainActor in
                            guard let self = self else { return }
                            let now = Date()
                            if now.timeIntervalSince(self.lastPeakTime) > 0.4 {
                                self.steps += 1
                                self.updateStepsSafe(self.steps)
                                self.lastPeakTime = now
                                print("🏃 Fallback Step detected: \(self.steps)")
                            }
                        }
                    }
                }
            }
        }
        
        // 3. Compass
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.05
            motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                let yaw = motion.attitude.yaw
                self?.heading = (yaw * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            }
        }
        
        // 4. Altimeter
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                self?.floorLevel = data.relativeAltitude.doubleValue
            }
        } else {
            print("⚠️ Altimeter not available")
        }
    }
    
    // Helper to keep the update logic clean
    private func updateStepsSafe(_ newTotal: Int) {
        if newTotal > self.steps {
            print("👟 Steps: \(newTotal)")
            self.steps = newTotal
            self.recordMovement()
        }
    }
    
    // MARK: - Data Recording
    private func recordMovement() {
        let node = PathNode(
            timestamp: Date(),
            stepCount: self.steps,
            heading: self.heading,
            floorLevel: self.floorLevel,
            side: .none,
            isVerified: false
        )
        self.path.append(node)
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
            if let text = node.aiLabel { story += "• Saw '\(text)' at step \(node.stepCount)\n" }
            if let obj = node.detectedObject { story += "• Detected \(obj) at step \(node.stepCount)\n" }
        }
        story += "• Finished with \(steps) steps."
        return story
    }
    
    // MARK: - Shutdown
    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        
        pollingTask?.cancel()
        pollingTask = nil
        
        pedometer.stopUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        visionService.stopSession()
        
        print("🛑 Session Finished.")
    }
}
