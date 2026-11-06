import AVFoundation
import SwiftUI
import UIKit

/// Steuert die Kamera: Vorschau, Foto aufnehmen, Kamera wechseln, Blitz.
final class CameraModel: NSObject, ObservableObject {
    enum Status { case idle, running, denied, unavailable }

    @Published var status: Status = .idle
    @Published var position: AVCaptureDevice.Position = .back
    @Published var flashOn = false
    @Published var capturedImage: UIImage?

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "pling.camera")
    private var input: AVCaptureDeviceInput?
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndRun()
                } else {
                    DispatchQueue.main.async { self?.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard self.configure(position: self.currentPosition) else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    /// Nur auf der Kamera-Queue lesen.
    private var currentPosition: AVCaptureDevice.Position = .back

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        session.commitConfiguration()
        return true
    }

    func flip() {
        queue.async { [weak self] in
            guard let self, self.configured else { return }
            let next: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            if self.configure(position: next) {
                self.currentPosition = next
                DispatchQueue.main.async { self.position = next }
            }
        }
    }

    func capture() {
        let flash = flashOn
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(.on) {
                settings.flashMode = flash ? .on : .off
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let normalized = ImageTools.normalized(image)
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = normalized
        }
    }
}

/// Zeigt das Live-Bild der Kamera.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
