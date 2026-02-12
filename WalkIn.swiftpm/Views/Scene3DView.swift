import SwiftUI
import SceneKit
import ARKit

struct Scene3DView: View {
    let path: [PathNode]
    let checkpoints: [CGPoint]
    let walls: [WallGeometry]? 
    let worldMap: ARWorldMap?
    var userPosition: (x: Float, y: Float, z: Float)? = nil // Optional live user position
    
    var body: some View {
        SceneView(
            scene: createScene(),
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .background(Color.black)
        .cornerRadius(12)

    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Add Point Cloud from World Map
        if let map = worldMap {
            addPointCloud(from: map, to: scene)
        }
        
        // Configure camera (Smart Auto-Focus)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        
        if !path.isEmpty {
            // Calculate Bounding Box center
            let minX = path.map { $0.position.x }.min() ?? 0
            let maxX = path.map { $0.position.x }.max() ?? 0
            let minZ = path.map { $0.position.z }.min() ?? 0
            let maxZ = path.map { $0.position.z }.max() ?? 0
            
            let centerX = (minX + maxX) / 2
            let centerZ = (minZ + maxZ) / 2
            
            // Set camera to look at center from above-back
            cameraNode.position = SCNVector3(x: centerX, y: 15, z: centerZ + 15) // High angle
            cameraNode.look(at: SCNVector3(centerX, 0, centerZ))
        } else {
            cameraNode.position = SCNVector3(x: 0, y: 5, z: 10)
            cameraNode.eulerAngles = SCNVector3(x: -Float.pi/6, y: 0, z: 0)
        }
        
        scene.rootNode.addChildNode(cameraNode)
        
        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white:0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        // Add directional light
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .directional
        lightNode.position = SCNVector3(x: 5, y: 10, z: 5)
        lightNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(lightNode)
        
        // Render building structure (blocks)
        addBuildingStructure(to: scene)
        
        // Add floor grid for reference
        addFloorGrid(to: scene)
        
        // Add User Avatar if position provided
        if let userPos = userPosition {
            let avatar = SCNSphere(radius: 0.3)
            avatar.firstMaterial?.diffuse.contents = UIColor.green
            avatar.firstMaterial?.emission.contents = UIColor.green
            let avatarNode = SCNNode(geometry: avatar)
            avatarNode.position = SCNVector3(userPos.x, userPos.y + 0.5, userPos.z)
            
            // Add pulse animation
            let scaleUp = SCNAction.scale(to: 1.5, duration: 0.5)
            let scaleDown = SCNAction.scale(to: 1.0, duration: 0.5)
            let sequence = SCNAction.sequence([scaleUp, scaleDown])
            avatarNode.runAction(SCNAction.repeatForever(sequence))
            
            scene.rootNode.addChildNode(avatarNode)
        }
        
        return scene
    }
    
    private func addBuildingStructure(to scene: SCNScene) {
        
        // 0. WALLS (Blueprint Style)
        if let walls = walls {
            for wall in walls {
                let plane = SCNBox(width: CGFloat(wall.extent[0]), height: CGFloat(wall.extent[1]), length: 0.1, chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor.white.withAlphaComponent(0.3)
                mat.isDoubleSided = true
                plane.materials = [mat]
                
                let wallNode = SCNNode(geometry: plane)
                // SceneKit plane is usually X-Y, ARKit plane is X-Z. 
                // However, our WallGeometry transform is likely already in world space.
                // But SCNBox is centered.
                // WallGeometry.transform is the center transform.
                
                wallNode.simdTransform = wall.transformMatrix
                
                // Add wireframe effect (border)
                let wireframe = SCNBox(width: CGFloat(wall.extent[0]), height: CGFloat(wall.extent[1]), length: 0.1, chamferRadius: 0)
                wireframe.firstMaterial?.fillMode = .lines
                wireframe.firstMaterial?.diffuse.contents = UIColor.white
                let wireNode = SCNNode(geometry: wireframe)
                wallNode.addChildNode(wireNode)
                
                scene.rootNode.addChildNode(wallNode)
            }
        }
    
        guard !path.isEmpty else { return }
        
        // Floor Level Tracking
        var floorLevels: Set<Int> = []
        
        // 1. PATH RENDERING (Continuous Tube)
        // We'll use cylinders between nodes
        for i in 0..<path.count - 1 {
            let start = path[i]
            let end = path[i+1]
            let startPos = SCNVector3(start.position.x, start.position.y, start.position.z)
            let endPos = SCNVector3(end.position.x, end.position.y, end.position.z)
            
            let distance = GLKVector3Distance(SscnVector3ToGlkVector3(startPos), SscnVector3ToGlkVector3(endPos))
            
            if distance > 0.05 { // Filter tiny jitters
                let cylinder = SCNCylinder(radius: 0.15, height: CGFloat(distance))
                cylinder.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.7)
                
                let lineNode = SCNNode(geometry: cylinder)
                lineNode.position = SCNVector3((startPos.x + endPos.x)/2, (startPos.y + endPos.y)/2, (startPos.z + endPos.z)/2)
                lineNode.look(at: endPos, up: scene.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
                scene.rootNode.addChildNode(lineNode)
            }
        }

        for (index, node) in path.enumerated() {
            let floorIndex = Int(round(node.position.y / 3.0))
            floorLevels.insert(floorIndex)
            
            // 2. LANDMARKS (Pins)
            if let label = node.aiLabel {
                addLandmarkPin(label, at: node.position, to: scene, isManual: node.isManualLandmark)
            } else if node.isManualLandmark {
                 addLandmarkPin("Mark", at: node.position, to: scene, isManual: true)
            }
        }
        
        // 4. FLOOR LEVEL LABELS
        for level in floorLevels {
            let floorY = Float(level) * 3.0
            addFloorLabel("Level \(level)", at: SCNVector3(-3, floorY, -3), to: scene)
        }
    }
    
    }
    
    private func SscnVector3ToGlkVector3(_ v: SCNVector3) -> GLKVector3 {
        return GLKVector3Make(v.x, v.y, v.z)
    }

    private func addLandmarkPin(_ text: String, at pos: SIMD3<Float>, to scene: SCNScene, isManual: Bool) {
        // Pin Head
        let sphere = SCNSphere(radius: 0.3)
        sphere.firstMaterial?.diffuse.contents = isManual ? UIColor.systemYellow : UIColor.systemCyan
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(pos.x, pos.y + 0.5, pos.z)
        
        // Pulse Action
        let scaleUp = SCNAction.scale(to: 1.2, duration: 1.0)
        let scaleDown = SCNAction.scale(to: 1.0, duration: 1.0)
        let pulse = SCNAction.repeatForever(SCNAction.sequence([scaleUp, scaleDown]))
        node.runAction(pulse)
        
        scene.rootNode.addChildNode(node)
        
        // Text Label
        let textGeom = SCNText(string: text, extrusionDepth: 0.05)
        textGeom.font = UIFont.systemFont(ofSize: 0.3, weight: .bold)
        textGeom.firstMaterial?.diffuse.contents = UIColor.white
        
        let textNode = SCNNode(geometry: textGeom)
        textNode.position = SCNVector3(pos.x, pos.y + 0.9, pos.z) // Above pin
        textNode.scale = SCNVector3(0.1, 0.1, 0.1)
        textNode.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(textNode)
    }
    
    private func addFloorLabel(_ text: String, at pos: SCNVector3, to scene: SCNScene) {
        let textGeom = SCNText(string: text, extrusionDepth: 0.1)
        textGeom.font = UIFont.systemFont(ofSize: 0.5, weight: .black)
        textGeom.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
        
        let node = SCNNode(geometry: textGeom)
        node.position = pos
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        node.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(node)
    }
        

    
    private func addFloorGrid(to scene: SCNScene) {
        let gridSize: Float = 20
        let gridSpacing: Float = 1.0
        
        for i in stride(from: -gridSize, through: gridSize, by: gridSpacing) {
            // Lines along X
            let lineGeometry = SCNCylinder(radius: 0.005, height: CGFloat(gridSize * 2))
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white.withAlphaComponent(0.1)
            lineGeometry.materials = [material]
            
            let lineNode = SCNNode(geometry: lineGeometry)
            lineNode.position = SCNVector3(i, -0.5, 0)
            lineNode.eulerAngles = SCNVector3(Float.pi/2, 0, Float.pi/2)
            scene.rootNode.addChildNode(lineNode)
            
            // Lines along Z
            let lineNode2 = SCNNode(geometry: lineGeometry)
            lineNode2.position = SCNVector3(0, -0.5, i)
            lineNode2.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
            scene.rootNode.addChildNode(lineNode2)
        }
    }
    
    private func addPointCloud(from map: ARWorldMap, to scene: SCNScene) {
        let points = map.rawFeaturePoints.points
        
        // Create efficient point cloud geometry
        var vertices: [SCNVector3] = []
        for (i, point) in points.enumerated() {
            if i % 3 == 0 { // Downsample for performance
                vertices.append(SCNVector3(point.x, point.y, point.z))
            }
        }
        
        guard !vertices.isEmpty else { return }
        
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: Array(0..<vertices.count).map { Int32($0) },
            primitiveType: .point
        )
        element.pointSize = 2.0
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 5.0
        
        let pointsGeometry = SCNGeometry(sources: [source], elements: [element])
        pointsGeometry.firstMaterial?.diffuse.contents = UIColor.yellow
        pointsGeometry.firstMaterial?.lightingModel = .constant
        
        let pointsNode = SCNNode(geometry: pointsGeometry)
        scene.rootNode.addChildNode(pointsNode)
    }


