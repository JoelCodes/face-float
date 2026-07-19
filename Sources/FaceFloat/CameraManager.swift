import AVFoundation
import Foundation

final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "facefloat.camera")
    private(set) var currentDevice: AVCaptureDevice?

    /// Called on the capture queue with each new frame.
    var frameHandler: ((CVPixelBuffer) -> Void)?
    /// Called on the main queue when the active device changes (e.g. unplug fallback).
    var deviceChanged: (() -> Void)?

    static func availableDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        return discovery.devices
    }

    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        NotificationCenter.default.addObserver(
            self, selector: #selector(deviceDisconnected(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
    }

    func start(deviceID: String?) {
        let devices = Self.availableDevices()
        let device = devices.first { $0.uniqueID == deviceID }
            ?? AVCaptureDevice.default(for: .video)
            ?? devices.first
        guard let device else { return }
        configure(device: device)
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure(device: AVCaptureDevice) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }
        currentDevice = device
    }

    @objc private func deviceDisconnected(_ note: Notification) {
        guard let gone = note.object as? AVCaptureDevice,
              gone.uniqueID == currentDevice?.uniqueID else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Settings.cameraID = nil
            self.start(deviceID: nil)
            self.deviceChanged?()
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameHandler?(buffer)
    }
}
