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
    nonisolated private let processingInterval = 0.2 // Process every 0.2 seconds
    
    // 🔥 FIX: Mark this as 'nonisolated(unsafe)' to fix the Main Actor error
    nonisolated(unsafe) private var yoloRequest: VNCoreMLRequest?
    
    func setup(with manager: NavigationManager) {
        self.navigationManager = manager
        
        // Load the Model manually (Detailed Debugging Enabled)
        setupYOLO()
        
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
    
    // 🔥 SMART LOADER: Searches everywhere for the file
    private func setupYOLO() {
        Task.detached {
            print("🚀 STARTING YOLO SETUP...")
            
            // 1. Try finding it in the Main Bundle
            var foundURL = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodel")
            
            // 2. If not found, try the "Class Bundle" (This is where Playground files usually live)
            if foundURL == nil {
                let classBundle = Bundle(for: VisionService.self)
                foundURL = classBundle.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodel")
            }
            
            // 3. If STILL not found, check inside the "Resources" subdirectory explicitly
            if foundURL == nil {
                foundURL = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodel", subdirectory: "Resources")
            }
            
            guard let modelURL = foundURL else {
                print("❌ CRITICAL ERROR: Could not find 'YOLOv3TinyInt8LUT.mlmodel' anywhere.")
                print("👉 FIX: Make sure you created a folder named 'Resources' and put the file inside.")
                return
            }
            
            print("✅ Found Model File at: \(modelURL.path)")
            
            do {
                print("🔨 Compiling Model...")
                let compiledURL = try MLModel.compileModel(at: modelURL)
                
                print("🧠 Loading CoreML Model...")
                let model = try MLModel(contentsOf: compiledURL)
                let visionModel = try VNCoreMLModel(for: model)
                
                let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                    self?.handleYOLO(request: request)
                }
                
                request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
                self.yoloRequest = request
                print("🎉 YOLO MODEL FULLY LOADED & READY!")
                
            } catch {
                print("❌ MODEL LOAD CRASHED: \(error)")
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
    
    // 🔥 HANDLE YOLO (Background Thread)
    nonisolated private func handleYOLO(request: VNRequest) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        // Lowered confidence to 0.4 (40%) to make it detect easier during testing
        let bestObjects = results.filter { $0.confidence > 0.4 }
        
        if let topObject = bestObjects.first {
            let label = topObject.labels.first?.identifier ?? "Unknown"
            let confidence = Int(topObject.confidence * 100)
            
            // Log to console so you can see it working
            print("📦 Detected: \(label) (\(confidence)%)")
            
            sendToManager(text: nil, object: label)
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
        
        // 1. Run YOLO (Now safe because of nonisolated(unsafe))
        if let yolo = self.yoloRequest {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: dynamicOrientation)
            try? handler.perform([yolo])
        }
        
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
