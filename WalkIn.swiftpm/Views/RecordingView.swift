import SwiftUI
@preconcurrency import AVFoundation

struct RecordingView: View {
    @ObservedObject var nav: NavigationManager
    @State private var currentState: Int = 0 // 0:Name, 1:Instruct, 2:Record
    @State private var mapName = ""
    
    var body: some View {
        ZStack {
            // PASS THE VISION SERVICE TO THE CAMERA HERE
            CameraPreview(visionService: nav.visionService)
                .opacity(currentState == 2 ? 1 : 0.4)
                .ignoresSafeArea()
            
            if currentState == 2 {
                // AR HUD
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mapName).font(.headline).foregroundColor(.white)
                            Text("\(nav.steps) steps").font(.largeTitle).bold().foregroundColor(.blue)
                                .shadow(color: .blue, radius: 10)
                        }
                        Spacer()
                    }
                    .padding(.top, 50).padding(.horizontal)
                    Spacer()
                    
                    // Visual feedback when AI finds something
                    if let lastNode = nav.path.last, let label = lastNode.aiLabel ?? lastNode.detectedObject {
                        Text("Detected: \(label)")
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                            .transition(.scale)
                    }
                    
                    Button("Finish Path") { nav.stopTracking() }
                        .padding().background(.thickMaterial).cornerRadius(20).padding(.bottom, 30)
                }
            } else {
                // Setup Flow
                VStack(spacing: 20) {
                    if currentState == 0 {
                        Text("Name Your Path").font(.title).foregroundColor(.white)
                        TextField("e.g. Library", text: $mapName)
                            .padding().background(Color.white.opacity(0.2)).cornerRadius(10).padding()
                        Button("Next") { currentState = 1 }
                            .disabled(mapName.isEmpty)
                            .padding().background(Color.blue).cornerRadius(10)
                    } else {
                        Text("Instructions").font(.title).foregroundColor(.white)
                        Text("1. Hold upright\n2. Walk steadily").foregroundColor(.white)
                        Button("Start") {
                            nav.startTracking()
                            currentState = 2
                        }.padding().background(Color.green).cornerRadius(10)
                    }
                }
                .padding(30).background(.ultraThinMaterial).cornerRadius(20).padding()
            }
        }
    }
}

// MARK: - FIXED CAMERA PREVIEW WITH DATA OUTPUT
struct CameraPreview: UIViewRepresentable {
    var visionService: VisionService // We need this to send frames
    
    func makeCoordinator() -> Coordinator {
        Coordinator(service: visionService)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return view }
        
        session.addInput(input)
        
        // --- THIS IS THE NEW PART: Output Video Data ---
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        // -----------------------------------------------
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.frame
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        
        DispatchQueue.global().async { session.startRunning() }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    // The Coordinator handles the data stream
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var service: VisionService
        
        init(service: VisionService) {
            self.service = service
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            // Extract the image buffer and send to Vision
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            service.processFrame(pixelBuffer)
        }
    }
}
