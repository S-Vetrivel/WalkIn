import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            // 1. Deep OLED Background
            Color.black.ignoresSafeArea()
            
            // 2. Full-Screen Infinite 3D Grid
            TimelineView(.animation) { timeline in
                let elapsedTime = timeline.date.timeIntervalSinceReferenceDate
                
                ZStack {
                    // The Grid itself
                    FullWidthPerspectiveGrid(elapsedTime: elapsedTime)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0), .blue.opacity(0.5), .blue.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    // Add a glow effect behind the lines
                        .shadow(color: .blue.opacity(0.5), radius: 5, x: 0, y: 0)
                }
            }
            .ignoresSafeArea()
            
            // 3. UI Layer
            VStack {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WalkIn")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        
                        Text("Indoor Navigation Engine")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue.opacity(0.9)) // Changed from gray to Blue
                    }
                    Spacer()
                    
                    // Removed the "Status Indicator" point completely
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                
                Spacer()
                
                // 4. "Hyper-Glass" Buttons
                VStack(spacing: 20) {
                    NavigationLink(value: AppRoute.activeRecording) {
                        AppleGlassButton(
                            title: "Start New Path",
                            subtitle: "Map a new location",
                            icon: "figure.walk.motion",
                            style: .primary
                        )
                    }
                    
                    NavigationLink(value: AppRoute.pathHistory) {
                        AppleGlassButton(
                            title: "Saved Paths",
                            subtitle: "View your history",
                            icon: "clock.arrow.circlepath",
                            style: .glass
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 🚀 The 3D Infinite Grid Engine

struct FullWidthPerspectiveGrid: Shape {
    var elapsedTime: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 60 // Wider grid for a cleaner look
        let offset = CGFloat(elapsedTime.truncatingRemainder(dividingBy: 1.0)) * step
        
        // Vertical Perspective Lines
        for x in stride(from: -rect.width, to: rect.width * 2, by: step) {
            path.move(to: CGPoint(x: x, y: rect.height))
            // Converge to a vanishing point high up
            path.addLine(to: CGPoint(x: rect.midX + (x - rect.midX) * 0.05, y: rect.height * -0.2))
        }
        
        // Horizontal Moving Lines
        for y in stride(from: 0, to: rect.height * 1.5, by: step) {
            let currentY = rect.height - ((y + offset).truncatingRemainder(dividingBy: rect.height * 1.5))
            if currentY > 0 {
                let scale = 0.05 + (0.95 * (currentY / rect.height))
                let w = rect.width * 4 * scale
                path.move(to: CGPoint(x: rect.midX - w/2, y: currentY))
                path.addLine(to: CGPoint(x: rect.midX + w/2, y: currentY))
            }
        }
        return path
    }
}

// MARK: - 💎 "Hyper-Glass" Button Component

enum ButtonStyleType {
    case primary
    case glass
}

struct AppleGlassButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let style: ButtonStyleType
    
    var body: some View {
        HStack(spacing: 15) {
            // Icon Container
            ZStack {
                Circle()
                    .fill(style == .primary ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Text Stack
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8)) // Brightened text
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .background {
            if style == .primary {
                // PRIMARY: Deep Blue Gradient
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 20, x: 0, y: 10)
            } else {
                // GLASS: The Real Effect
                ZStack {
                    // Layer 1: The Blur
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thinMaterial)
                    
                    // Layer 2: White Tint (Reflection)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        // Common Border (The Rim Light)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style == .primary ? 0.3 : 0.6),
                            Color.white.opacity(style == .primary ? 0.1 : 0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }
}
