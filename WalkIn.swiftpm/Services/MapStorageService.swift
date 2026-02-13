import Foundation
import ARKit
class MapStorageService: @unchecked Sendable {
    static let shared = MapStorageService()
    
    private let fileName = "saved_maps.json"
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var fileURL: URL {
        let url = documentsDirectory.appendingPathComponent(fileName)
        print("📁 MapStorageService File URL: \(url.path)")
        return url
    }
    
    // MARK: - Save
    func saveMap(name: String, nodes: [PathNode], totalSteps: Int, startTime: Date, walls: [WallGeometry]? = nil, obstaclePoints: [simd_float3]? = nil, mappingStatus: String? = "Limited") -> SavedMap {
        let duration = Date().timeIntervalSince(startTime)
        
        // Flatten obstacle points
        var flatObstacles: [Float] = []
        if let points = obstaclePoints {
            flatObstacles = points.flatMap { [$0.x, $0.y, $0.z] }
        }
        
        // Generate Landmark Map
        var landmarkMap: [UUID: String] = [:]
        for node in nodes {
            if let label = node.aiLabel {
                landmarkMap[node.id] = label
            }
        }
        
        var newMap = SavedMap(
            name: name,
            createdAt: Date(),
            nodes: nodes,
            totalSteps: totalSteps,
            duration: duration
        )
        newMap.walls = walls
        newMap.obstaclePoints = flatObstacles
        newMap.landmarkMap = landmarkMap
        newMap.worldMappingStatus = mappingStatus
        
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
    // MARK: - World Map Storage
    
    func saveWorldMapData(_ data: Data, mapId: UUID) throws {
        let mapURL = documentsDirectory.appendingPathComponent("\(mapId.uuidString).arworldmap")
        try data.write(to: mapURL)
    }
    
    func loadWorldMap(mapId: UUID) -> ARWorldMap? {
        let mapURL = documentsDirectory.appendingPathComponent("\(mapId.uuidString).arworldmap")
        guard FileManager.default.fileExists(atPath: mapURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: mapURL)
            let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
            return worldMap
        } catch {
            print("❌ Error loading world map: \(error)")
            return nil
        }
    }
}
