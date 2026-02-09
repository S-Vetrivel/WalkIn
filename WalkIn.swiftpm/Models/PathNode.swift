import Foundation

struct PathNode: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    
    // Sensors
    let stepCount: Int
    let heading: Double
    let floorLevel: Double
    
    // AI Data (The "Eyes")
    var aiLabel: String?       // Text (OCR) e.g., "Room 302"
    var detectedObject: String? // Object e.g., "Water Cooler"
    var summary: String?        // Narrative e.g., "Walked past Room 302"
    
    var side: RelativeSide = .none
    var isVerified: Bool = false
    
    enum RelativeSide: String, Codable {
        case left, right, front, none
    }
}
