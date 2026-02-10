import SwiftUI

struct PathVisualizer: View {
    let path: [PathNode]
    
    var body: some View {
        Canvas { context, size in
            guard !path.isEmpty else { return }
            
            // 1. Calculate Bounds
            var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
            var points: [CGPoint] = []
            
            var currentX = 0.0
            var currentY = 0.0
            points.append(CGPoint(x: 0, y: 0))
            
            // Convert Steps + Heading to X,Y
            // We assume 1 step ~= 0.7 meters
            let stepLength = 0.7
            
            for i in 1..<path.count {
                let node = path[i]
                let prevNode = path[i-1]
                let stepDiff = Double(node.stepCount - prevNode.stepCount)
                
                // Angle in radians (Education standard: 0 is East, but for Map usually 0 is North)
                // Let's assume standard math: 0 East. Compass Heading 0 is North.
                // Compass 0 -> Math 90 (pi/2)
                // Compass 90 -> Math 0
                // MathAngle = (90 - compass) * pi / 180
                let angle = (90.0 - node.heading) * .pi / 180.0
                
                let dx = cos(angle) * stepDiff * stepLength
                let dy = -sin(angle) * stepDiff * stepLength // Y is flipped in screens
                
                currentX += dx
                currentY += dy
                
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
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
