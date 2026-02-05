import Foundation

struct PathNode: Codable, Identifiable {
    // MARK: - Core Identity
    var id = UUID()
    let timestamp: Date // Essential for speed and sync analysis
    
    // MARK: - Physical Sensor Data
    let stepCount: Int      // Cumulative steps from start
    let heading: Double     // Magnetometer/Gyro degree (0-359)
    let floorLevel: Double  // Barometer-based altitude
    
    // MARK: - AI Detection Data
    var aiLabel: String?        // Text recognized via OCR (e.g., "Room 402")
    var detectedObject: String? // Object found via CoreML (e.g., "Fire Extinguisher")
    var aiConfidence: Double    // Score from 0.0 to 1.0
    
    // MARK: - User Context & Edits
    var userLabel: String?      // Manual override (e.g., "My Library")
    var side: RelativeSide      // Is the landmark on the Left or Right?
    var isVerified: Bool        // Did the user confirm the AI detection?
    var userNote: String?       // Extra metadata (e.g., "Board is near the water cooler")
    
    // Helper Enum for Side Detection
    enum RelativeSide: String, Codable {
        case left, right, front, none
    }
}
