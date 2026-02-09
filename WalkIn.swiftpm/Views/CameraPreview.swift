import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    // 1. Create the View
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoOrientation = .portrait // Default start
        return view
    }
    
    // 2. Update Layout & Orientation
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // This ensures the camera fills the screen even if you rotate
        uiView.videoPreviewLayer.session = session
        uiView.updateOrientation()
    }
    
    // 3. Internal UIKit View Class (The Engine)
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        // This fixes the "Rotated/Inverted" issue
        func updateOrientation() {
            guard let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported else { return }
            
            // Get the current device orientation
            let orientation = UIDevice.current.orientation
            
            switch orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft // Cameras are often opposite
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                // If the device is flat on a table, keep the last known orientation
                // or default to Portrait for the "WalkIn" use case
                connection.videoOrientation = .portrait
            }
            
            // Force the layer to fill the new bounds
            videoPreviewLayer.frame = bounds
        }
        
        // Auto-update layout when the screen size changes
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
            updateOrientation()
        }
    }
}
