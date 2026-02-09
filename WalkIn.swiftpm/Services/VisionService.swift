import Foundation
import AVFoundation
import Vision
import UIKit

// 1. Main Actor for UI Safety
@MainActor
class VisionService: NSObject, ObservableObject {
    @Published var captureSession: AVCaptureSession?
    weak var navigationManager: NavigationManager?
    
    // Safety Flags
    nonisolated(unsafe) private var lastProcessingTime = Date()
    nonisolated private let processingInterval = 0.2 // Very Fast Scanning (5x per second)
    
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
        
        Task.detached {
            let session = AVCaptureSession()
            session.sessionPreset = .high // High Res for better OCR
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            
            if session.canAddInput(input) { session.addInput(input) }
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "aiQueue"))
            if session.canAddOutput(output) { session.addOutput(output) }
            
            session.startRunning()
            
            await MainActor.run {
                self.captureSession = session
            }
        }
    }
    
    func stopSession() {
        captureSession?.stopRunning()
    }
    
    private func sendToManager(text: String?, object: String?) {
        self.navigationManager?.updateAIContext(text: text, object: object)
    }
}

// 2. The Delegate (Background Thread)
extension VisionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else { return }
        lastProcessingTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 🔥 CRITICAL FIX: Calculate Dynamic Orientation
        // This ensures the AI reads text correctly whether you are in Portrait OR Landscape.
        let dynamicOrientation = self.currentUIOrientation()
        
        // A. TEXT REQUEST (OCR)
        let textRequest = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            // "Loose" Filter: Accept almost anything
            let topTexts = observations.compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.count > 1 }
            
            if let bestText = topTexts.first {
                print("👁️ READ: \(bestText)") // Console Debug
                Task { @MainActor in
                    self.sendToManager(text: bestText, object: nil)
                }
            }
        }
        textRequest.recognitionLevel = .accurate // Accurate is better for Monitors
        textRequest.usesLanguageCorrection = false // Read raw codes/numbers better
        
        // B. OBJECT REQUEST
        let objectRequest = VNClassifyImageRequest { request, _ in
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            
            // Super Low Confidence for Testing (20%)
            if let bestObj = observations.first(where: { $0.confidence > 0.2 }) {
                let id = bestObj.identifier
                Task { @MainActor in
                    self.sendToManager(text: nil, object: id)
                }
            }
        }
        
        // Run AI with the Correct Orientation
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: dynamicOrientation)
        try? handler.perform([textRequest, objectRequest])
    }
    
    // 3. Orientation Helper (The Magic Logic)
    nonisolated private func currentUIOrientation() -> CGImagePropertyOrientation {
        // We act as if the device is Portrait to map the sensor correctly
        let deviceOrientation = UIDevice.current.orientation
        
        switch deviceOrientation {
        case .portrait:
            return .right
        case .landscapeLeft:
            return .down // Sensor is opposite
        case .landscapeRight:
            return .up
        case .portraitUpsideDown:
            return .left
        default:
            return .right // Default fallback
        }
    }
}
