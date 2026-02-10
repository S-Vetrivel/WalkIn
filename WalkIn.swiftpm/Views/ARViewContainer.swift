import SwiftUI
import ARKit
import SceneKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var navManager: NavigationManager
    var path: [PathNode]
    
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
        context.coordinator.updatePathNodes(path: path, targetIndex: navManager.targetNodeIndex, mode: navManager.mode)
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
        
        func updatePathNodes(path: [PathNode], targetIndex: Int, mode: NavigationManager.SessionMode) {
            guard let arView = arView else { return }
            
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
    }
}
