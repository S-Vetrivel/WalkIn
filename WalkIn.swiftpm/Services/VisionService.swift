import Vision
import AVFoundation

// @unchecked Sendable tells Swift: "I will handle thread safety, don't worry."
class VisionService: NSObject, ObservableObject, @unchecked Sendable {
    // Weak reference to avoid memory leaks
    weak var navigationManager: NavigationManager?
    
    // Simple throttle variables
    private var lastScanTime: Date = Date()
    private let scanInterval: TimeInterval = 1.0
    
    // This must be MainActor so NavigationManager can call it safely
    @MainActor
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
    }
    
    // Called by the Camera Coordinator on a background thread
    func processFrame(_ buffer: CVPixelBuffer) {
        // 1. Simple Throttle Check
        let now = Date()
        if now.timeIntervalSince(lastScanTime) < scanInterval { return }
        lastScanTime = now
        
        // 2. Define Requests
        
        // A. TEXT REQUEST
        let textRequest = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self = self else { return } // Safe unwrap
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let topCandidate = observations.first?.topCandidates(1).first
            
            if let text = topCandidate?.string, text.count > 3 {
                if ["EXIT", "PUSH", "PULL"].contains(text.uppercased()) { return }
                
                // FIX: Explicitly capture self weakly again for the async block
                DispatchQueue.main.async { [weak self] in
                    self?.handleDetection(text: text, object: nil)
                }
            }
        }
        textRequest.recognitionLevel = .accurate
        
        // B. OBJECT REQUEST
        let objectRequest = VNClassifyImageRequest { [weak self] request, _ in
            guard let self = self else { return } // Safe unwrap
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            
            if let bestResult = observations.first(where: { $0.confidence > 0.8 }) {
                let interestingObjects = ["computer keyboard", "monitor", "water bottle", "desk", "fire extinguisher", "printer", "laptop"]
                let identifier = bestResult.identifier.lowercased()
                
                if interestingObjects.contains(where: { identifier.contains($0) }) {
                    let cleanName = identifier.components(separatedBy: ",").first ?? identifier
                    
                    // FIX: Explicitly capture self weakly again for the async block
                    DispatchQueue.main.async { [weak self] in
                        self?.handleDetection(text: nil, object: cleanName)
                    }
                }
            }
        }
        
        // 3. execute requests
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try? handler.perform([textRequest, objectRequest])
    }
    
    // Removed @MainActor here because we are already calling it inside DispatchQueue.main.async
    // This avoids the double-check confusion for the compiler.
    private func handleDetection(text: String?, object: String?) {
        // We are on Main Thread, so it's safe to call the actor-isolated manager
        if let text = text {
            print("👁️ AI Saw: \(text)")
            Task { @MainActor in
                navigationManager?.recordNode(label: text, side: .right, isAI: true)
            }
        }
        if let object = object {
            print("🧠 AI Found: \(object)")
            Task { @MainActor in
                navigationManager?.recordNode(object: object, side: .right, isAI: true)
            }
        }
    }
}
