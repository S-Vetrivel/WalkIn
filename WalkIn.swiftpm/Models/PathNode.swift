import Foundation
import simd
import ARKit

struct PathNode: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    
    // Sensors
    let stepCount: Int
    let heading: Double
    let floorLevel: Double
    
    // AR World Transform (The "Anchor")
    // We store the 4x4 matrix as a flat array of 16 floats because simd_float4x4 isn't Codable by default
    let transformMatrix: [Float]
    
    // Helper to get/set the actual simd_float4x4
    var transform: simd_float4x4 {
        get {
            guard transformMatrix.count == 16 else { return matrix_identity_float4x4 }
            return simd_float4x4(
                simd_float4(transformMatrix[0], transformMatrix[1], transformMatrix[2], transformMatrix[3]),
                simd_float4(transformMatrix[4], transformMatrix[5], transformMatrix[6], transformMatrix[7]),
                simd_float4(transformMatrix[8], transformMatrix[9], transformMatrix[10], transformMatrix[11]),
                simd_float4(transformMatrix[12], transformMatrix[13], transformMatrix[14], transformMatrix[15])
            )
        }
    }
    
    // Helper for position (column 3)
    var position: SIMD3<Float> {
        let col3 = transform.columns.3
        return SIMD3<Float>(col3.x, col3.y, col3.z)
    }
    
    // AI Data (The "Eyes")
    var image: String?          // Relative path to saved image (for visual alignment)
    var aiLabel: String?       // Text (OCR) e.g., "Room 302"
    var detectedObject: String? // Object e.g., "Water Cooler"
    var summary: String?        // Narrative e.g., "Walked past Room 302"
    
    var side: RelativeSide = .none
    var isVerified: Bool = false
    
    enum RelativeSide: String, Codable {
        case left, right, front, none
    }
    
    // Init with matrix
    init(timestamp: Date, stepCount: Int, heading: Double, floorLevel: Double, transform: simd_float4x4, image: String? = nil, aiLabel: String? = nil, detectedObject: String? = nil) {
        self.timestamp = timestamp
        self.stepCount = stepCount
        self.heading = heading
        self.floorLevel = floorLevel
        
        // Flatten matrix
        let c0 = transform.columns.0
        let c1 = transform.columns.1
        let c2 = transform.columns.2
        let c3 = transform.columns.3
        
        self.transformMatrix = [
            c0.x, c0.y, c0.z, c0.w,
            c1.x, c1.y, c1.z, c1.w,
            c2.x, c2.y, c2.z, c2.w,
            c3.x, c3.y, c3.z, c3.w
        ]
        
        self.image = image
        self.aiLabel = aiLabel
        self.detectedObject = detectedObject
        self.side = .none
        self.isVerified = false
    }
}

// Environmental Geometry
struct WallGeometry: Codable, Identifiable {
    var id: UUID = UUID()
    let center: [Float] // [x, y, z]
    let extent: [Float] // [width, height, length] (Plane extent is usually X-Z in ARKit local space)
    let transform: [Float] // 16-element matrix
    
    // Helpers
    var center3: SIMD3<Float> {
        guard center.count == 3 else { return .zero }
        return SIMD3<Float>(center[0], center[1], center[2])
    }
    
    var extent3: SIMD3<Float> {
        guard extent.count == 3 else { return .zero }
        return SIMD3<Float>(extent[0], extent[1], extent[2])
    }
    
    var transformMatrix: simd_float4x4 {
        guard transform.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            simd_float4(transform[0], transform[1], transform[2], transform[3]),
            simd_float4(transform[4], transform[5], transform[6], transform[7]),
            simd_float4(transform[8], transform[9], transform[10], transform[11]),
            simd_float4(transform[12], transform[13], transform[14], transform[15])
        )
    }
    
    init(anchor: ARPlaneAnchor) {
        self.id = anchor.identifier
        self.center = [anchor.center.x, anchor.center.y, anchor.center.z]
        self.extent = [anchor.extent.x, anchor.extent.y, anchor.extent.z]
        
        // Transform
        let t = anchor.transform
        self.transform = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
        ]
    }
}
