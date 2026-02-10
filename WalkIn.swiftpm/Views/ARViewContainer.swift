import SwiftUI
import ARKit
import SceneKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var navManager: NavigationManager
    var path: [PathNode]
    var targetNodeIndex: Int
    var mode: NavigationManager.SessionMode
    
    // We use a shared session from ARManager
    let session = ARManager.shared.session
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        
        // Critical: Connect to the shared session
        arView.session = session
        arView.delegate = context.coordinator
        
        // Debug options (optional, good for verifying feature points)
        // arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true
        
        // Context for Coordinator
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Here we update the scene based on path data
        context.coordinator.updatePathNodes(path: path, targetIndex: targetNodeIndex, mode: mode)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        var arView: ARSCNView?
        var renderedNodeIds: Set<UUID> = []
        var nodeMap: [UUID: SCNNode] = [:]
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // Local state for renderer loop (avoiding MainActor / EnvironmentObject access)
        var currentPath: [PathNode] = []
        var currentTargetIndex: Int = 0
        var currentMode: NavigationManager.SessionMode = .idle
        
        func updatePathNodes(path: [PathNode], targetIndex: Int, mode: NavigationManager.SessionMode) {
            guard let arView = arView else { return }
            
            // Update local state for renderer
            self.currentPath = path
            self.currentTargetIndex = targetIndex
            self.currentMode = mode
            
            // Render new nodes
            for (index, nodeData) in path.enumerated() {
                if !renderedNodeIds.contains(nodeData.id) {
                    addSpheres(for: nodeData, to: arView)
                    renderedNodeIds.insert(nodeData.id)
                }
                
                // Update Color based on state
                if let node = nodeMap[nodeData.id] {
                    updateNodeAppearance(node, index: index, targetIndex: targetIndex, mode: mode)
                }
            }
            
            // Optional: Remove nodes that are no longer in path (if path clearing is supported)
            if path.isEmpty && !renderedNodeIds.isEmpty {
                arView.scene.rootNode.enumerateChildNodes { (node, stop) in
                    if node.name?.starts(with: "PathNode") == true {
                        node.removeFromParentNode()
                    }
                }
                renderedNodeIds.removeAll()
                nodeMap.removeAll()
            }
            
            // Update Arrow State
            updateArrow(targetIndex: targetIndex, path: path, mode: mode)
        }
        
        private func addSpheres(for nodeData: PathNode, to arView: ARSCNView) {
            // Create a blue sphere
            let sphere = SCNSphere(radius: 0.05) // 5cm radius
            sphere.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.9)
            sphere.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.5)
            
            let node = SCNNode(geometry: sphere)
            node.simdTransform = nodeData.transform
            node.name = "PathNode-\(nodeData.id)"
            
            // Add a subtle animation (pulse)
            let scaleUp = SCNAction.scale(to: 1.2, duration: 1.0)
            let scaleDown = SCNAction.scale(to: 1.0, duration: 1.0)
            let pulse = SCNAction.repeatForever(SCNAction.sequence([scaleUp, scaleDown]))
            node.runAction(pulse)
            
            arView.scene.rootNode.addChildNode(node)
            nodeMap[nodeData.id] = node
        }
        
        private func updateNodeAppearance(_ node: SCNNode, index: Int, targetIndex: Int, mode: NavigationManager.SessionMode) {
            guard let material = node.geometry?.firstMaterial else { return }
            
            if mode == .navigating {
                if index < targetIndex {
                    // Past nodes - Fade out or turn green
                    material.diffuse.contents = UIColor.green.withAlphaComponent(0.3)
                    node.opacity = 0.5
                } else if index == targetIndex {
                    // Target node - Bright Yellow/Orange and pulsing
                    material.diffuse.contents = UIColor.orange
                    material.emission.contents = UIColor.orange
                    node.opacity = 1.0
                    node.scale = SCNVector3(1.2, 1.2, 1.2)
                } else {
                    // Future nodes - Blue
                    material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.6)
                    material.emission.contents = UIColor.clear
                    node.opacity = 0.8
                    node.scale = SCNVector3(1.0, 1.0, 1.0)
                }
            } else {
                // Recording mode - all cyan
                material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.9)
            }
        }
        
        // MARK: - Arrow Logic
        var arrowNode: SCNNode?
        
        func updateArrow(targetIndex: Int, path: [PathNode], mode: NavigationManager.SessionMode) {
            guard let arView = arView, mode == .navigating, targetIndex < path.count else {
                arrowNode?.removeFromParentNode()
                arrowNode = nil
                return
            }
            
            // Create arrow if needed
            if arrowNode == nil {
                createArrow()
            }
            
            // Position and Rotation are handled in renderer callback for smoothness
        }
        
        private func createArrow() {
            guard let arView = arView else { return }
            
            // Simple Arrow Geometry: Pyramid (Cone) + Cylinder
            let cone = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.15)
            cone.firstMaterial?.diffuse.contents = UIColor.yellow
            let coneNode = SCNNode(geometry: cone)
            coneNode.position = SCNVector3(0, 0, -0.1) // Tip forward
            coneNode.eulerAngles.x = -Float.pi / 2 // Point -Z
            
            let cylinder = SCNCylinder(radius: 0.02, height: 0.2)
            cylinder.firstMaterial?.diffuse.contents = UIColor.yellow
            let cylinderNode = SCNNode(geometry: cylinder)
            cylinderNode.position = SCNVector3(0, 0, 0.1)
            cylinderNode.eulerAngles.x = -Float.pi / 2
            
            arrowNode = SCNNode()
            arrowNode?.addChildNode(coneNode)
            arrowNode?.addChildNode(cylinderNode)
            
            arView.scene.rootNode.addChildNode(arrowNode!)
        }
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arrow = arrowNode,
                  let pointOfView = arView?.pointOfView,
                  currentMode == .navigating,
                  currentTargetIndex < currentPath.count
            else { return }
            
            let targetNode = currentPath[currentTargetIndex]
            let targetPos = SCNVector3(targetNode.position.x, targetNode.position.y, targetNode.position.z)
            
            // Position arrow 1 meter in front of camera, slightly down
            let currentPos = pointOfView.position
             // pointOfView.transform gives us the camera's orientation matrix
             // The 3rd column (index 2) is the backward vector (-Z)
             // The 2nd column (index 1) is the up vector (+Y)
             // The 1st column (index 0) is the right vector (+X)
             
            let transform = pointOfView.transform
            let orientation = SCNVector3(-transform.m31, -transform.m32, -transform.m33) // Forward vector
            let up = SCNVector3(transform.m21, transform.m22, transform.m23)
            
            // We want 1m forward and 0.3m down relative to camera
            let forwardDist: Float = 1.0
            let downDist: Float = 0.3
            
            let finalPos = SCNVector3(
                currentPos.x + orientation.x * forwardDist - up.x * downDist,
                currentPos.y + orientation.y * forwardDist - up.y * downDist,
                currentPos.z + orientation.z * forwardDist - up.z * downDist
            )
            
            arrow.position = finalPos
            
            // Point at target
            arrow.look(at: targetPos)
        }
        
    }
}
