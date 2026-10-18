import AVFoundation

struct CameraInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Wraps an AVCaptureSession that delivers BGRA frames to a delegate.
final class CameraCapture {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "lagcam.capture-session")

    /// Real cameras only: the OBS Virtual Camera is excluded so we never feed ourselves.
    static func availableCameras() -> [CameraInfo] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        return discovery.devices
            .filter { $0.uniqueID != VirtualCameraSink.obsDeviceUID && !$0.localizedName.contains("OBS") }
            .map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(
        deviceID: String?,
        delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        delegateQueue: DispatchQueue,
        completion: @escaping (Bool) -> Void
    ) {
        sessionQueue.async { [self] in
            let ids = Self.availableCameras().map(\.id)
            guard let id = deviceID.flatMap({ ids.contains($0) ? $0 : nil }) ?? ids.first,
                  let device = AVCaptureDevice(uniqueID: id),
                  let newInput = try? AVCaptureDeviceInput(device: device)
            else {
                completion(false)
                return
            }

            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
            }
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            } else {
                session.sessionPreset = .high
            }
            if session.outputs.isEmpty {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            output.setSampleBufferDelegate(delegate, queue: delegateQueue)
            session.commitConfiguration()

            if !session.isRunning { session.startRunning() }
            completion(session.isRunning)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}
