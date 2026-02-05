import Foundation

// This is the "Breadcrumb" structure for your PDR system
struct PathNode: Codable, Identifiable {
    var id = UUID()           // Unique ID for each point
    let stepCount: Int       // Total steps at this point
    let heading: Double      // Direction the user was facing
    let floorLevel: Double   // Altitude from the Barometer
    let landmarkLabel: String? // Optional: "Exit Sign", "Blue Door"
    let timestamp: Date      // To calculate walking speed later
}
