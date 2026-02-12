import Foundation
import AVFoundation
import Vision
import UIKit


// 1. Main Actor for UI Safety
@MainActor
class VisionService: NSObject, ObservableObject {
    @Published var captureSession: AVCaptureSession?
    weak var navigationManager: NavigationManager?
    
    // Safety Flags - nonisolated(unsafe) lets background threads touch them
    nonisolated(unsafe) private var lastProcessingTime = Date()
    nonisolated private let processingInterval = 0.2 // Process every 0.2 seconds
    

    
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
        

        
        // Start Camera in Background
        Task.detached {
            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            
            if session.canAddInput(input) { session.addInput(input) }
            
            let output = AVCaptureVideoDataOutput()
            // We pass 'self' safely because we handled the isolation below
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
    
    // Send to Manager (Main Thread)
    nonisolated private func sendToManager(text: String?, object: String?) {
        Task { @MainActor in
            self.navigationManager?.updateAIContext(text: text, object: object)
        }
    }
    
    // 🔥 HANDLE VISION RESULTS (Generic)

    nonisolated private func handleVisionResults(request: VNRequest) {
        // No-op or handle specific non-ML requests if any
        if let _ = request.results as? [VNRecognizedTextObservation] {
             // Let OCR pass through or handle its own specific callback
        } else {
            // print("⚠️ Vision: Unknown result type: \(type(of: request.results?.first))")
        }
    }


}

// 2. The Delegate (Background Thread)
extension VisionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else { return }
        lastProcessingTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let dynamicOrientation = self.currentUIOrientation()
        

        
        // 2. Run OCR
        let textRequest = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let fullText = observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            
            if fullText.count > 2 {
                print("👁️ OCR: \(fullText)")
                self.sendToManager(text: fullText, object: nil)
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: dynamicOrientation)
        try? handler.perform([textRequest])
    }
    
    nonisolated private func currentUIOrientation() -> CGImagePropertyOrientation {
        // Hardcode to .right to match typical Landscape/Portrait camera buffers without accessing UIDevice on background thread
        return .right
    }
}
