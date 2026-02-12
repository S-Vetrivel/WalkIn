import Foundation
import ARKit
import UIKit
import Vision
import ImageIO

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
        // Resize for better Vision features (720px width)
        guard let resized = image.resized(toWidth: 720) else { return nil }
        return saveImage(resized, name: "\(nodeId.uuidString).jpg", compression: 0.6)
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
    
    /// Generates Feature Print directly from PixelBuffer (Faster & Correct Orientation)
    func generateFeaturePrint(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        
        // Use orientation to match saved images (which are usually .up after UIImage save, or .right before save)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print("❌ Feature Print Error: \(error)")
            return nil
        }
    }
    
    /// Generates a FeaturePrintObservation for a given UIImage (Legacy/Fallback)
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
            // Vision distance: 0 is identical. 
            // We want a score where 1.0 is identical.
            // Distance > 15-20 is usually a poor match.
            // Let's normalize it so distance 0.0 -> 1.0, distance 20.0 -> 0.0
            let maxDistance: Float = 20.0
            let score = 1.0 - (distance / maxDistance)
            return max(0, min(1.0, score))
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

