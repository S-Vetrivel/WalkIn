import SwiftUI
import SceneKit

struct Scene3DView: View {
    let path: [PathNode]
    let checkpoints: [CGPoint]
    
    var body: some View {
        SceneView(
            scene: createScene(),
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .background(Color.black)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
        )
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Configure camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 5, z: 10)
        cameraNode.eulerAngles = SCNVector3(x: -Float.pi/6, y: 0, z: 0)
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
        
        // Render path nodes as spheres
        for (index, node) in path.enumerated() {
            let sphere = SCNSphere(radius: 0.08)
            let material = SCNMaterial()
            
            // Color based on position
            if index == 0 {
                // Start - Green
                material.diffuse.contents = UIColor.systemGreen
                material.emission.contents = UIColor.systemGreen.withAlphaComponent(0.3)
            } else if index == path.count - 1 {
                // Current - Red (pulsing)
                material.diffuse.contents = UIColor.systemRed
                material.emission.contents = UIColor.systemRed.withAlphaComponent(0.5)
            } else {
                // Path - Cyan
                material.diffuse.contents = UIColor.systemCyan
                material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.2)
            }
            
            material.specular.contents = UIColor.white
            sphere.materials = [material]
            
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = SCNVector3(node.position.x, node.position.y, node.position.z)
            scene.rootNode.addChildNode(sphereNode)
            
            // Add text label for landmarks
            if let label = node.aiLabel {
                let text = SCNText(string: label, extrusionDepth: 0.02)
                text.font = UIFont.systemFont(ofSize: 0.3, weight: .bold)
                text.flatness = 0.01
                text.firstMaterial?.diffuse.contents = UIColor.yellow
                text.firstMaterial?.emission.contents = UIColor.yellow.withAlphaComponent(0.5)
                
                let textNode = SCNNode(geometry: text)
                textNode.position = SCNVector3(node.position.x, node.position.y + 0.15, node.position.z)
                textNode.scale = SCNVector3(0.1, 0.1, 0.1)
                
                // Make text face camera
                textNode.constraints = [SCNBillboardConstraint()]
                
                scene.rootNode.addChildNode(textNode)
            }
            
            // Connect to previous node with cylinder
            if index > 0 {
                let previousNode = path[index - 1]
                let dx = node.position.x - previousNode.position.x
                let dy = node.position.y - previousNode.position.y
                let dz = node.position.z - previousNode.position.z
                let distance = sqrt(dx*dx + dy*dy + dz*dz)
                
                if distance > 0.01 {
                    let cylinder = SCNCylinder(radius: 0.02, height: CGFloat(distance))
                    let cylinderMaterial = SCNMaterial()
                    cylinderMaterial.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.6)
                    cylinderMaterial.emission.contents = UIColor.systemCyan.withAlphaComponent(0.1)
                    cylinder.materials = [cylinderMaterial]
                    
                    let cylinderNode = SCNNode(geometry: cylinder)
                    
                    // Position at midpoint
                    let midX = (node.position.x + previousNode.position.x) / 2
                    let midY = (node.position.y + previousNode.position.y) / 2
                    let midZ = (node.position.z + previousNode.position.z) / 2
                    cylinderNode.position = SCNVector3(midX, midY, midZ)
                    
                    // Rotate to connect nodes
                    cylinderNode.look(at: SCNVector3(node.position.x, node.position.y, node.position.z))
                    cylinderNode.eulerAngles.x += Float.pi / 2
                    
                    scene.rootNode.addChildNode(cylinderNode)
                }
            }
        }
        
        // Add checkpoints as yellow spheres
        for checkpoint in checkpoints {
            let sphere = SCNSphere(radius: 0.12)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow
            material.emission.contents = UIColor.systemYellow.withAlphaComponent(0.4)
            material.transparency = 0.7
            sphere.materials = [material]
            
            let checkpointNode = SCNNode(geometry: sphere)
            checkpointNode.position = SCNVector3(Float(checkpoint.x), 0, Float(checkpoint.y))
            scene.rootNode.addChildNode(checkpointNode)
        }
        
        // Add floor grid for reference
        addFloorGrid(to: scene)
        
        return scene
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
}
