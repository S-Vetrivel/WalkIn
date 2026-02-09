import Foundation
import AVFoundation
import Vision
import UIKit
import CoreML

// 1. Main Actor for UI Safety
@MainActor
class VisionService: NSObject, ObservableObject {
    @Published var captureSession: AVCaptureSession?
    weak var navigationManager: NavigationManager?
    
    // Safety Flags - nonisolated(unsafe) lets background threads touch them
    nonisolated(unsafe) private var lastProcessingTime = Date()
    nonisolated private let processingInterval = 0.2
    
    // 🔥 FIX 1: Mark this as 'nonisolated(unsafe)' to fix the Main Actor error
    nonisolated(unsafe) private var yoloRequest: VNCoreMLRequest?
    
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
        
        // Load the Model manually (No Xcode auto-gen needed)
        setupYOLO()
        
        Task.detached {
            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720
            
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
    
    // 🔥 THE NEW MANUAL LOADER
    private func setupYOLO() {
        Task.detached {
            do {
                print("📂 Attempting to load YOLO model manually...")
                
                // 1. Find the raw file in the app bundle
                guard let modelURL = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodel") else {
                    print("❌ Error: Could not find 'YOLOv3TinyInt8LUT.mlmodel' in the bundle.")
                    return
                }
                
                // 2. Compile it on the fly (Bypasses Xcode's build system issues)
                let compiledURL = try MLModel.compileModel(at: modelURL)
                
                // 3. Load the compiled model
                let model = try MLModel(contentsOf: compiledURL)
                let visionModel = try VNCoreMLModel(for: model)
                
                // 4. Create the request
                let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                    self?.handleYOLO(request: request)
                }
                
                // Explicit type to avoid errors
                request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
                
                // 5. Save safely
                self.yoloRequest = request
                print("✅ YOLO Model Loaded Successfully!")
                
            } catch {
                print("❌ Failed to load YOLO Model: \(error)")
            }
        }
    }
    
    func stopSession() {
        captureSession?.stopRunning()
    }
    
    nonisolated private func sendToManager(text: String?, object: String?) {
        Task { @MainActor in
            self.navigationManager?.updateAIContext(text: text, object: object)
        }
    }
    
    nonisolated private func handleYOLO(request: VNRequest) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        // Filter for confidence > 60%
        let bestObjects = results.filter { $0.confidence > 0.6 }
        
        if let topObject = bestObjects.first {
            let label = topObject.labels.first?.identifier ?? "Unknown"
            // print("🧠 YOLO Found: \(label)") 
            sendToManager(text: nil, object: label)
        }
    }
}

extension VisionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else { return }
        lastProcessingTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let dynamicOrientation = self.currentUIOrientation()
        
        // Run YOLO
        if let yolo = self.yoloRequest {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: dynamicOrientation)
            try? handler.perform([yolo])
        }
        
        // Run OCR
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
        // 🔥 FIX 3: UIDevice is MainActor, so we use a safe fallback on background threads
        return .right
    }
}
