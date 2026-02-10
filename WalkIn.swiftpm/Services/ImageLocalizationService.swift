import Foundation
import ARKit
import UIKit
import Vision

class ImageLocalizationService: @unchecked Sendable {
    static let shared = ImageLocalizationService()
    
    private let fileManager = FileManager.default
    
    // Directory to save reference images
    private var imagesDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("ReferenceImages", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {}
    
    // MARK: - Saving
    
    /// Saves a UIImage as a JPEG and returns the relative path (filename).
    func saveReferenceImage(_ image: UIImage, for mapId: UUID) -> String? {
        // High quality for start image
        return saveImage(image, name: "\(mapId.uuidString).jpg", compression: 0.8)
    }
    
    /// Saves a per-node image (highly compressed/downscaled)
    func saveNodeImage(_ image: UIImage, nodeId: UUID) -> String? {
        // Resize to something reasonable for Vision (e.g. 640px width is plenty)
        // For Playground safety <25MB, we aggressively compress
        guard let resized = image.resized(toWidth: 480) else { return nil }
        return saveImage(resized, name: "\(nodeId.uuidString).jpg", compression: 0.5)
    }
    
    private func saveImage(_ image: UIImage, name: String, compression: CGFloat) -> String? {
        guard let data = image.jpegData(compressionQuality: compression) else { return nil }
        let fileURL = imagesDirectory.appendingPathComponent(name)
        do {
            try data.write(to: fileURL)
            return name
        } catch {
            print("❌ Error saving image: \(error)")
            return nil
        }
    }
    
    // MARK: - Loading & Vision
    
    func loadUIImage(filename: String) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    func loadReferenceImage(filename: String, physicalWidth: CGFloat = 0.5) -> ARReferenceImage? {
        guard let image = loadUIImage(filename: filename), let cgImage = image.cgImage else { return nil }
        let ref = ARReferenceImage(cgImage, orientation: .up, physicalWidth: physicalWidth)
        ref.name = filename
        return ref
    }
    
    // MARK: - Feature Prints
    
    /// Generates a FeaturePrintObservation for a given image
    func generateFeaturePrint(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print("❌ Feature Print Error: \(error)")
            return nil
        }
    }
    
    /// Computes similarity between two feature prints (0.0 to 1.0)
    func computeSimilarity(between observationA: VNFeaturePrintObservation, and observationB: VNFeaturePrintObservation) -> Float {
        var distance: Float = 0
        do {
            try observationA.computeDistance(&distance, to: observationB)
            // Vision returns "distance" (0 = identical, large = different).
            // We want "similarity". Normalizing can be tricky, but usually 0.0 is exact match then it grows.
            // Let's assume a Euclidean-like distance.
            // A common heuristic: similarity = 1 / (1 + distance) or just thresholds.
            // Let's return the RAW distance for now, caller decides threshold.
            // ACTUALLY, Master prompt says "Similarity threshold".
            // Distance of 0 is high similarity. Distance of 1+ is low.
            // Let's invert it roughly: 1.0 - min(distance, 1.0)
            return 1.0 - min(distance, 1.0)
        } catch {
            return 0.0
        }
    }
}

// Helper
extension UIImage {
    func resized(toWidth width: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

