import Foundation

struct SavedMap: Codable, Identifiable {
    var id = UUID()
    let name: String
    let createdAt: Date
    let nodes: [PathNode]
    let totalSteps: Int
    let duration: TimeInterval // in seconds
    
    // Computed helper for display
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
