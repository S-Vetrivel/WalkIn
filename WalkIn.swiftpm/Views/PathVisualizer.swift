import SwiftUI

struct PathVisualizer: View {
    let path: [PathNode]
    let checkpoints: [CGPoint]
    
    var body: some View {
        Canvas { context, size in
            guard !path.isEmpty else { return }
            
            // 1. Calculate Bounds
            var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
            var points: [CGPoint] = []
            
            for node in path {
                let currentX = Double(node.position.x)
                let currentY = Double(node.position.z) // Top-down view uses Z for Y axis
                
                points.append(CGPoint(x: currentX, y: currentY))
                
                minX = min(minX, currentX)
                maxX = max(maxX, currentX)
                minY = min(minY, currentY)
                maxY = max(maxY, currentY)
            }
            
            // 2. Scale to Fit
            let width = maxX - minX
            let height = maxY - minY
            let padding = 20.0
            
            // Avoid division by zero
            let scaleX = width > 0 ? (Double(size.width) - 2 * padding) / width : 1.0
            let scaleY = height > 0 ? (Double(size.height) - 2 * padding) / height : 1.0
            let scale = min(scaleX, scaleY)
            
            // Center the map
            let offsetX = (Double(size.width) - width * scale) / 2.0 - minX * scale
            let offsetY = (Double(size.height) - height * scale) / 2.0 - minY * scale
            
            // 3. Draw Path
            var pathPath = Path()
            if let first = points.first {
                pathPath.move(to: CGPoint(x: Double(first.x) * scale + offsetX, y: Double(first.y) * scale + offsetY))
            }
            
            for point in points.dropFirst() {
                pathPath.addLine(to: CGPoint(x: Double(point.x) * scale + offsetX, y: Double(point.y) * scale + offsetY))
            }
            
            context.stroke(pathPath, with: .color(.cyan), lineWidth: 3)
            
            // 4. Draw Landmarks
            for (index, node) in path.enumerated() {
                if index < points.count {
                    let point = points[index]
                    let screenPoint = CGPoint(x: Double(point.x) * scale + offsetX, y: Double(point.y) * scale + offsetY)
                    
                    if node.aiLabel != nil {
                        // Draw text marker
                        let circle = Path(ellipseIn: CGRect(x: screenPoint.x - 4, y: screenPoint.y - 4, width: 8, height: 8))
                        context.fill(circle, with: .color(.yellow))
                    } else if node.detectedObject != nil {
                        // Draw object marker
                        let rect = Path(roundedRect: CGRect(x: screenPoint.x - 4, y: screenPoint.y - 4, width: 8, height: 8), cornerRadius: 2)
                        context.fill(rect, with: .color(.orange))
                    }
                }
            }
            
            // 5. Draw Current Position (Last Point)
            if let last = points.last {
                let screenLast = CGPoint(x: Double(last.x) * scale + offsetX, y: Double(last.y) * scale + offsetY)
                let currentPos = Path(ellipseIn: CGRect(x: screenLast.x - 6, y: screenLast.y - 6, width: 12, height: 12))
                context.fill(currentPos, with: .color(.red))
            }
            
            // 6. Draw Checkpoints (Waypoints)
            for checkpoint in checkpoints {
                let screenCheckpoint = CGPoint(
                    x: Double(checkpoint.x) * scale + offsetX,
                    y: Double(checkpoint.y) * scale + offsetY
                )
                
                // Outer Circle (White border)
                let outerCircle = Path(ellipseIn: CGRect(x: screenCheckpoint.x - 8, y: screenCheckpoint.y - 8, width: 16, height: 16))
                context.stroke(outerCircle, with: .color(.white), lineWidth: 2)
                
                // Inner Circle (Yellow fill)
                let innerCircle = Path(ellipseIn: CGRect(x: screenCheckpoint.x - 6, y: screenCheckpoint.y - 6, width: 12, height: 12))
                context.fill(innerCircle, with: .color(.yellow))
            }
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
