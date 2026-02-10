import Foundation
import simd

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
    var aiLabel: String?       // Text (OCR) e.g., "Room 302"
    var detectedObject: String? // Object e.g., "Water Cooler"
    var summary: String?        // Narrative e.g., "Walked past Room 302"
    
    var side: RelativeSide = .none
    var isVerified: Bool = false
    
    enum RelativeSide: String, Codable {
        case left, right, front, none
    }
    
    // Init with matrix
    init(timestamp: Date, stepCount: Int, heading: Double, floorLevel: Double, transform: simd_float4x4, aiLabel: String? = nil, detectedObject: String? = nil) {
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
        
        self.aiLabel = aiLabel
        self.detectedObject = detectedObject
        self.side = .none
        self.isVerified = false
    }
}
