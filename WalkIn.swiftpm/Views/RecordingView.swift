//
//  RecordingView.swift
//  WalkIn
//
//  Created by Apple on 05/02/26.
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @ObservedObject var nav: NavigationManager
    
    // UI State
    @State private var showInstructions = false
    @State private var isRecording = false
    @State private var hasCameraPermission = false
    
    var body: some View {
        ZStack {
            // LAYER 1: The Camera Background
            if hasCameraPermission {
                CameraPreview()
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
                Text("Camera Permission Needed")
                    .foregroundColor(.white)
            }
            
            // LAYER 2: The Interface Overlay
            VStack {
                // Top Bar: Live Status
                if isRecording {
                    HStack {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                            .padding(.leading)
                        Text("REC").font(.caption).bold().foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.top, 50)
                }
                
                Spacer()
                
                // Sensor Dashboard (Only shows when recording)
                if isRecording {
                    HStack(spacing: 20) {
                        // Steps Card
                        SensorCardView(icon: "figure.walk", value: "\(nav.steps)", label: "Steps", color: .blue)
                        // Heading Card
                        SensorCardView(icon: "safari.fill", value: String(format: "%.0f°", nav.heading), label: "Heading", color: .orange)
                    }
                    .padding()
                    .transition(.move(edge: .bottom))
                }
                
                // Bottom Control Area
                VStack {
                    if isRecording {
                        // STOP BUTTON
                        Button(action: {
                            stopRecording()
                        }) {
                            Label("Stop & Save", systemImage: "stop.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        // START BUTTON
                        Button(action: {
                            showInstructions = true
                        }) {
                            Label("Start Navigation", systemImage: "play.circle.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Material.ultraThinMaterial)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            checkCameraPermission()
        }
        // THE INSTRUCTION POPUP
        .sheet(isPresented: $showInstructions) {
            VStack(spacing: 20) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Ready to Walk?")
                    .font(.largeTitle).bold()
                
                VStack(alignment: .leading, spacing: 15) {
                    InstructionRow(icon: "1.circle.fill", text: "Hold your device upright.")
                    InstructionRow(icon: "2.circle.fill", text: "Walk at a steady pace.")
                    InstructionRow(icon: "3.circle.fill", text: "Tap 'Stop' when you reach your destination.")
                }
                .padding()
                
                Button(action: {
                    startRecording()
                }) {
                    Text("I Understand, Let's Go!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.top)
            }
            .padding()
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    
    // Logic Functions
    func startRecording() {
        showInstructions = false
        isRecording = true
        nav.startTracking()
    }
    
    func stopRecording() {
        isRecording = false
        nav.stopTracking()
        // Here you could add navigation back to home if needed
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { hasCameraPermission = granted }
            }
        default:
            hasCameraPermission = false
        }
    }
}

// MARK: - Helper Views

struct SensorCardView: View {
    let icon: String; let value: String; let label: String; let color: Color
    var body: some View {
        VStack {
            Image(systemName: icon).font(.largeTitle).foregroundColor(color)
            Text(value).font(.title2).bold()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Material.regular) // Glass effect
        .cornerRadius(12)
    }
}

struct InstructionRow: View {
    let icon: String; let text: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.secondary)
            Text(text).font(.body)
        }
    }
}

// MARK: - Camera Preview Implementation
// This puts the live camera feed into a SwiftUI View
struct CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return view }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return view }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Run session on background thread to prevent UI lag
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
