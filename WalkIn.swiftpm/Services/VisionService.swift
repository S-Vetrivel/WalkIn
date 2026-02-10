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
    
    // 🔥 SMART LOADER: Handles raw model loading to bypass build system conflicts
    private func setupYOLO() {
        Task.detached {
            print("🚀 STARTING YOLO SETUP...")
            
            // 1. Search for the raw model file
            var foundURL: URL?
            let filename = "YOLOv3TinyInt8LUT"
            let ext = "mlmodel_raw"
            
            // detailed logging to find where the resource is
             let bundles = [Bundle.main, Bundle(for: VisionService.self)]
             for (index, bundle) in bundles.enumerated() {
                 print("📦 Scanning Bundle \(index): \(bundle.bundlePath)")
                 if let url = bundle.url(forResource: filename, withExtension: ext) {
                     print("   ✅ Found in root of bundle!")
                     foundURL = url
                     break
                 }
                 if let url = bundle.url(forResource: filename, withExtension: ext, subdirectory: "AIModels") {
                     print("   ✅ Found in AIModels subdirectory!")
                     foundURL = url
                     break
                 }
             }

            guard let sourceURL = foundURL else {
                print("❌ CRITICAL ERROR: Could not find '\(filename).\(ext)' anywhere.")
                return
            }
            
            print("✅ Found Raw Model File at: \(sourceURL.path)")
            
            do {
                // 2. Copy to a temporary location with correct extension (.mlmodel)
                let fileManager = FileManager.default
                let tempDirectory = fileManager.temporaryDirectory
                let tempModelURL = tempDirectory.appendingPathComponent("YOLOv3TinyInt8LUT.mlmodel")
                
                // Remove existing file if present
                if fileManager.fileExists(atPath: tempModelURL.path) {
                    try fileManager.removeItem(at: tempModelURL)
                }
                
                try fileManager.copyItem(at: sourceURL, to: tempModelURL)
                print("📋 Copied to temp: \(tempModelURL.path)")

                // 3. Compile the model
                print("🔨 Compiling Model...")
                let compiledURL = try MLModel.compileModel(at: tempModelURL)
                
                print("🧠 Loading CoreML Model...")
                let model = try MLModel(contentsOf: compiledURL)
                let visionModel = try VNCoreMLModel(for: model)
                
                let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                    self?.handleYOLO(request: request)
                }
                
request.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop                self.yoloRequest = request
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
        guard let results = request.results as? [VNRecognizedObjectObservation] else { 
            print("⚠️ YOLO: No results or wrong observation type")
            return 
        }
        
        if results.isEmpty {
            print("🔍 YOLO: Frame processed, but no objects seen (results empty)")
        } else {
            print("📊 YOLO: Found \(results.count) potential objects")
        }
        
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
            do {
                try handler.perform([yolo])
            } catch {
                print("❌ YOLO Execution Error: \(error)")
            }
        } else {
            // print("⏳ YOLO: Waiting for model to load...")
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
