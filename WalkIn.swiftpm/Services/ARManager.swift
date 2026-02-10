import Foundation
import ARKit
import Combine

@MainActor
class ARManager: NSObject, ObservableObject, ARSessionDelegate {
    static let shared = ARManager()
    
    @Published var session = ARSession()
    @Published var currentFrame: ARFrame?
    @Published var cameraTransform: simd_float4x4?
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    
    // Status message for the UI
    @Published var statusMessage: String = "Initializing AR..."
    
    override init() {
        super.init()
        session.delegate = self
    }
    
    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "ARKit not supported on this device."
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal] 
        // We might want to enable environment texturing for realistic lighting
        configuration.environmentTexturing = .automatic
        
        // Reset tracking to start fresh
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        statusMessage = "AR Session Started. Move device to map area."
    }
    
    func pauseSession() {
        session.pause()
        statusMessage = "AR Session Paused."
    }
    
    // MARK: - ARSessionDelegate
    
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
             self.currentFrame = frame
             self.cameraTransform = frame.camera.transform
        }
    }
    
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            self.trackingState = camera.trackingState
            switch camera.trackingState {
            case .notAvailable:
                self.statusMessage = "Tracking unavailable."
            case .limited(let reason):
                switch reason {
                case .initializing:
                    self.statusMessage = "Initializing AR..."
                case .excessiveMotion:
                    self.statusMessage = "Too much motion. Slow down."
                case .insufficientFeatures:
                    self.statusMessage = "Not enough light or details."
                case .relocalizing:
                    self.statusMessage = "Relocalizing..."
                @unknown default:
                    self.statusMessage = "Limited tracking."
                }
            case .normal:
                self.statusMessage = "Tracking Normal."
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "AR Error: \(error.localizedDescription)"
        }
    }
    
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.statusMessage = "AR Session Interrupted."
        }
    }
    
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.statusMessage = "AR Session Resumed."
            // Optionally reset tracking if interruption was long
        }
    }
}
