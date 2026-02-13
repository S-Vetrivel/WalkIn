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
    
    func updateUIView(_: ARSCNView, context: Context) {
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
        
        @MainActor
        func updatePathNodes(path: [PathNode], targetIndex: Int, mode: NavigationManager.SessionMode) {
            guard let arView = arView else { return }
            
            // Update local state for renderer
            self.currentPath = path
            self.currentTargetIndex = targetIndex
            self.currentMode = mode
            
            // Render new nodes
            // Note: ARSCNView.scene is MainActor isolated.
            for (index, nodeData) in path.enumerated() {
                if !renderedNodeIds.contains(nodeData.id) {
                    addSpheres(for: nodeData, to: arView)
                    renderedNodeIds.insert(nodeData.id)
                }
                
                // Update Transform (Relocalization)
                if let node = nodeMap[nodeData.id] {
                     // Apply World Offset to the original node transform
                     // storedTransform is in "Map Space".
                     // currentWorldOffset transforms "Map Space" to "Current AR Space".
                     let correctedTransform = nodeData.transform
                     node.simdTransform = correctedTransform
                     
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
        
        @MainActor
        private func addSpheres(for nodeData: PathNode, to arView: ARSCNView) {
            // Determine if this is a manual landmark
            let isLandmark = nodeData.isManualLandmark && nodeData.aiLabel != nil
            
            // Create sphere — yellow for landmarks, cyan for regular
            let sphere = SCNSphere(radius: isLandmark ? 0.07 : 0.05)
            if isLandmark {
                sphere.firstMaterial?.diffuse.contents = UIColor.yellow.withAlphaComponent(0.9)
                sphere.firstMaterial?.emission.contents = UIColor.yellow.withAlphaComponent(0.5)
            } else {
                sphere.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.9)
                sphere.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.5)
            }
            
            let node = SCNNode(geometry: sphere)
            node.simdTransform = nodeData.transform
            node.name = "PathNode-\(nodeData.id)"
            
            // Add a subtle animation (pulse)
            let scaleUp = SCNAction.scale(to: 1.2, duration: 1.0)
            let scaleDown = SCNAction.scale(to: 1.0, duration: 1.0)
            let pulse = SCNAction.repeatForever(SCNAction.sequence([scaleUp, scaleDown]))
            node.runAction(pulse)
            
            // Add floating 3D text label for landmarks
            if isLandmark, let labelText = nodeData.aiLabel {
                let text = SCNText(string: labelText, extrusionDepth: 0.5)
                text.font = UIFont.boldSystemFont(ofSize: 4)
                text.flatness = 0.2
                text.firstMaterial?.diffuse.contents = UIColor.yellow
                text.firstMaterial?.emission.contents = UIColor.yellow.withAlphaComponent(0.4)
                
                let textNode = SCNNode(geometry: text)
                // Scale down text to AR world size
                textNode.scale = SCNVector3(0.01, 0.01, 0.01)
                // Center the text horizontally
                let (_, maxBound) = textNode.boundingBox
                let textWidth = maxBound.x - textNode.boundingBox.min.x
                textNode.position = SCNVector3(
                    -textWidth * 0.01 / 2.0,  // Center X
                    0.12,                       // Above the sphere
                    0
                )
                
                // Billboard constraint — text always faces camera
                let billboardConstraint = SCNBillboardConstraint()
                billboardConstraint.freeAxes = [.X, .Y]
                textNode.constraints = [billboardConstraint]
                
                node.addChildNode(textNode)
            }
            
            arView.scene.rootNode.addChildNode(node)
            nodeMap[nodeData.id] = node
        }
        
        @MainActor
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
        
        @MainActor
        func updateArrow(targetIndex: Int, path: [PathNode], mode: NavigationManager.SessionMode) {
            guard let arView = arView else { return }
            let arrowNode = arView.scene.rootNode.childNode(withName: "NavArrow", recursively: false)
            
            guard mode == .navigating, targetIndex < path.count else {
                arrowNode?.removeFromParentNode()
                return
            }
            
            // Create arrow if needed
            let arrow: SCNNode
            if let existing = arrowNode {
                arrow = existing
            } else {
                createArrow()
                // Retrieve it back (it was just added)
                guard let newArrow = arView.scene.rootNode.childNode(withName: "NavArrow", recursively: false) else { return }
                arrow = newArrow
            }
            
            // Update Position
            guard let pointOfView = arView.pointOfView else { return }
            
            let targetNode = path[targetIndex]
            // APPLY WORLD OFFSET TO TARGET NODE POSITION FOR ARROW
            // We use the passed-in currentWorldOffset which is updated in updatePathNodes
            let targetTransform = targetNode.transform
            let targetPos = SCNVector3(targetTransform.columns.3.x, targetTransform.columns.3.y, targetTransform.columns.3.z)
            
            let currentPos = pointOfView.position
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
            
            // Smooth movement? SCNTransaction?
            // Since this is per-frame (via SwiftUI update), direct set is fine.
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.1
            arrow.position = finalPos
            arrow.look(at: targetPos)
            SCNTransaction.commit()
        }
        
        @MainActor
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
            
            let arrowNode = SCNNode()
            arrowNode.name = "NavArrow"
            arrowNode.addChildNode(coneNode)
            arrowNode.addChildNode(cylinderNode)
            
            arView.scene.rootNode.addChildNode(arrowNode)
        }
        // MARK: - ARSCNViewDelegate (Plane Detection)
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            // Visualize Planes
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            
            let gridNode = createGridNode(anchor: planeAnchor)
            node.addChildNode(gridNode)
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let gridNode = node.childNodes.first,
                  let planeGeometry = gridNode.geometry as? SCNPlane else { return }
            
            // Update size
            planeGeometry.width = CGFloat(planeAnchor.extent.x)
            planeGeometry.height = CGFloat(planeAnchor.extent.z)
            
            // Update position (center of the plane)
            gridNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
            
            // Update texture tiling based on size (1 tile per meter)
            if let material = planeGeometry.firstMaterial {
                material.diffuse.contentsTransform = SCNMatrix4MakeScale(planeAnchor.extent.x, planeAnchor.extent.z, 1)
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
            }
        }
        
        // MARK: - Grid Generation
        
        private func createGridNode(anchor: ARPlaneAnchor) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(anchor.extent.x), height: CGFloat(anchor.extent.z))
            
            let material = SCNMaterial()
            material.diffuse.contents = createGridTexture()
            material.transparency = 0.5
            material.isDoubleSided = true
            
            // Repeat texture (1 tile per meter)
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(anchor.extent.x, anchor.extent.z, 1)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            
            plane.materials = [material]
            
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(anchor.center.x, 0, anchor.center.z)
            // Rotate flat on the ground (Planes are X-Z, SCNPlane is X-Y)
            node.eulerAngles.x = -.pi / 2
            
            return node
        }
        
        private func createGridTexture() -> UIImage {
            let size = CGSize(width: 100, height: 100) // 10cm x 10cm tile resolution? No, map 1 tile = 1 meter visually?
            // Let's say 50px = 1 meter? No.
            // If scale is (extent.x, extent.z), then the texture is repeated X times.
            // If texture is 512x512, repeated X times.
            // Let's create a simple square with a border.
            
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.clear.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                
                // Draw Grid Lines
                let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
                UIColor.cyan.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 3 // Thicker lines
                path.stroke()
                
                // Detailed inner cross?
                // context.cgContext.move(to: CGPoint(x: 0, y: 50)); context.cgContext.addLine(to: CGPoint(x: 100, y: 50))
                // context.cgContext.move(to: CGPoint(x: 50, y: 0)); context.cgContext.addLine(to: CGPoint(x: 50, y: 100))
                // context.cgContext.strokePath()
            }
        }
    }
}
