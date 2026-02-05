import Foundation
import CoreMotion
import Combine

// Marking the class @MainActor helps protect the UI state
@MainActor
class NavigationManager: ObservableObject {
    // 1. Mark these as 'nonisolated' so they can live outside the MainActor logic if needed
    // or keep them private so they are just internal tools.
    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    
    @Published var steps: Int = 0
    @Published var heading: Double = 0.0
    @Published var floorLevel: Double = 0.0
    @Published var isTracking: Bool = false
    @Published var path: [PathNode] = []
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        // --- 1. PEDOMETER FIX ---
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                // ERROR FIX: Extract the simple types (Int/Double) HERE, before the Task
                guard let data = data else { return }
                let newSteps = data.numberOfSteps.intValue
                
                // Now send ONLY the safe 'Int' to the Main Actor
                Task { @MainActor in
                    self?.steps = newSteps
                }
            }
        }
        
        // --- 2. HEADING FIX ---
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            // Use 'to: .main' so the callback happens directly on the Main Thread
            // This avoids the concurrency hop entirely!
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                self?.heading = motion.attitude.yaw * (180 / .pi)
            }
        }
        
        // --- 3. ALTIMETER FIX ---
        if CMAltimeter.isRelativeAltitudeAvailable() {
            // Again, use 'to: .main' to stay safe
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                self?.floorLevel = data.relativeAltitude.doubleValue
            }
        }
    }
    
    func stopTracking() {
        pedometer.stopUpdates()
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        isTracking = false
        
        // Save the final node
        let node = PathNode(
            stepCount: steps,
            heading: heading,
            floorLevel: floorLevel,
            landmarkLabel: "End Point",
            timestamp: Date()
        )
        path.append(node)
    }
}
