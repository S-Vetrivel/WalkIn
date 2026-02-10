import Foundation

@MainActor
class MapStorageService {
    static let shared = MapStorageService()
    
    private let fileName = "saved_maps.json"
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var fileURL: URL {
        documentsDirectory.appendingPathComponent(fileName)
    }
    
    // MARK: - Save
    func saveMap(name: String, nodes: [PathNode], totalSteps: Int, startTime: Date) -> SavedMap {
        let duration = Date().timeIntervalSince(startTime)
        let newMap = SavedMap(
            name: name,
            createdAt: Date(),
            nodes: nodes,
            totalSteps: totalSteps,
            duration: duration
        )
        
        var currentMaps = loadMaps()
        currentMaps.insert(newMap, at: 0) // Add to top
        
        persist(maps: currentMaps)
        return newMap
    }
    
    // MARK: - Load
    func loadMaps() -> [SavedMap] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let maps = try JSONDecoder().decode([SavedMap].self, from: data)
            return maps
        } catch {
            print("❌ Error loading maps: \(error)")
            return []
        }
    }
    
    // MARK: - Delete
    func deleteMap(id: UUID) {
        var currentMaps = loadMaps()
        currentMaps.removeAll { $0.id == id }
        persist(maps: currentMaps)
    }
    
    // MARK: - Helper
    private func persist(maps: [SavedMap]) {
        do {
            let data = try JSONEncoder().encode(maps)
            try data.write(to: fileURL)
            print("✅ Maps saved successfully via MapStorageService")
        } catch {
            print("❌ Error saving maps to disk: \(error)")
        }
    }
}
