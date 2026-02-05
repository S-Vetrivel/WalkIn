import Foundation
import CoreMotion
import Combine

@MainActor
class NavigationManager: ObservableObject {
    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    
    // Add the Vision Service
    let visionService = VisionService()
    
    @Published var steps: Int = 0
    @Published var heading: Double = 0.0
    @Published var floorLevel: Double = 0.0
    @Published var isTracking: Bool = false
    @Published var path: [PathNode] = []
    
    // NO INIT HERE - Setup happens in startTracking to avoid data races
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        // LINKING IS SAFE NOW: Both classes are @MainActor
        visionService.setup(with: self)
        
        // 1. Pedometer
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let data = data else { return }
                let newSteps = data.numberOfSteps.intValue
                Task { @MainActor in self?.steps = newSteps }
            }
        }
        
        // 2. Heading
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                self?.heading = motion.attitude.yaw * (180 / .pi)
            }
        }
        
        // 3. Altimeter
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                self?.floorLevel = data.relativeAltitude.doubleValue
            }
        }
    }
    
    // MARK: - UPDATED RECORD FUNCTION
    // Accepts 'object' for physical things (Fire Extinguisher) AND 'label' for text (Library)
    func recordNode(label: String? = nil, object: String? = nil, side: PathNode.RelativeSide = .none, isAI: Bool = false) {
        let node = PathNode(
            timestamp: Date(),
            stepCount: self.steps,
            heading: self.heading,
            floorLevel: self.floorLevel,
            
            // Logic: Save text or object depending on what was found
            aiLabel: isAI ? label : nil,
            detectedObject: isAI ? object : nil,
            
            aiConfidence: isAI ? 0.9 : 0.0,
            userLabel: isAI ? nil : label,
            side: side,
            isVerified: !isAI,
            userNote: nil
        )
        self.path.append(node)
    }
    
    func stopTracking() {
        pedometer.stopUpdates()
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        isTracking = false
        recordNode(label: "End Point")
        print("Path recorded with \(path.count) nodes.")
    }
}
