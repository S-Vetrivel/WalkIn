import Foundation

import Vision
import UIKit


// 1. Main Actor for UI Safety
@MainActor
class VisionService: NSObject, ObservableObject {
    // Removed captureSession as we use ARKit's feed now
    weak var navigationManager: NavigationManager?
    
    // Safety Flags
    nonisolated(unsafe) private var lastProcessingTime = Date()
    nonisolated private let processingInterval = 0.5 // Process every 0.5 seconds (Throttled)
    
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
    }
    
    func stopSession() {
        // No-op since we don't own the session anymore
    }
    
    // Send to Manager (Main Thread)
    nonisolated private func sendToManager(text: String?, object: String?) {
        Task { @MainActor in
            self.navigationManager?.updateAIContext(text: text, object: object)
        }
    }
    
    // MARK: - Process External Frame (ARKit)
    nonisolated func process(pixelBuffer: CVPixelBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else { return }
        lastProcessingTime = now
        
        let dynamicOrientation: CGImagePropertyOrientation = .right // ARKit buffers are usually .right
        
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
        
        // Run classification/detection here if needed
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: dynamicOrientation)
        try? handler.perform([textRequest])
    }
}
