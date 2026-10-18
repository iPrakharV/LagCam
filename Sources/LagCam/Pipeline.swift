import Accelerate
import AVFoundation
import CoreImage
import QuartzCore

struct PipelineStatus: Equatable {
    var mode: Mode = .normal
    var label = "Normal"
    var scripted = false
    var sinkConnected = false
    var cameraRunning = false
}

/// Camera → EffectsEngine → OBS virtual camera, at a steady 30 fps.
/// Everything except the public command methods runs on `queue`.
final class Pipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let width = 1280
    static let height = 720
    static let fps = 30.0

    var onStatus: ((PipelineStatus) -> Void)?
    var onPreview: ((CGImage) -> Void)?

    private let queue = DispatchQueue(label: "lagcam.pipeline", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let engine = EffectsEngine()
    private let sink = VirtualCameraSink()
    private let capture = CameraCapture()
    private let renderColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let outputRect = CGRect(x: 0, y: 0, width: Pipeline.width, height: Pipeline.height)

    private var timer: DispatchSourceTimer?
    private var latest: CIImage?
    private var lastEmitted: CIImage?
    private var lastOutputBuffer: CVPixelBuffer?
    private var bgraPool: CVPixelBufferPool?
    private var uyvyPool: CVPixelBufferPool?
    private var yuvInfo = vImage_ARGBToYpCbCr()
    private var status = PipelineStatus()
    private var cameraRunning = false
    private var lastSinkCheck: Double = 0
    private var tick = 0
    private var previewEnabled = false

    override init() {
        super.init()
        bgraPool = Self.makePool(format: kCVPixelFormatType_32BGRA, minimumCount: 3)
        uyvyPool = Self.makePool(format: kCVPixelFormatType_422YpCbCr8, minimumCount: 6)
        var range = vImage_YpCbCrPixelRange(
            Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240,
            YpMax: 235, YpMin: 16, CbCrMax: 240, CbCrMin: 16)
        vImageConvert_ARGBToYpCbCr_GenerateConversion(
            kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2, &range, &yuvInfo,
            kvImageARGB8888, kvImage422CbYpCrYp8, vImage_Flags(kvImageNoFlags))
    }

    // MARK: Commands (any thread)

    func start(cameraID: String?) {
        selectCamera(cameraID)
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            t.schedule(deadline: .now(), repeating: 1 / Self.fps, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.renderTick() }
            t.resume()
            timer = t
        }
    }

    func stop() {
        capture.stop()
        queue.sync {
            timer?.cancel()
            timer = nil
            sink.disconnect()
        }
    }

    func selectCamera(_ id: String?) {
        capture.start(deviceID: id, delegate: self, delegateQueue: queue) { [weak self] running in
            self?.queue.async { self?.cameraRunning = running }
        }
    }

    func setMode(_ mode: Mode) { queue.async { self.engine.setMode(mode) } }
    func setIntensity(_ value: Double) { queue.async { self.engine.intensity = value } }
    func setPreviewEnabled(_ on: Bool) { queue.async { self.previewEnabled = on } }

    func startDisconnect(duration: Double) {
        queue.async { self.engine.startDisconnect(now: CACurrentMediaTime(), duration: duration) }
    }

    func startReconnect() {
        queue.async { self.engine.startReconnect(now: CACurrentMediaTime()) }
    }

    // MARK: Camera input

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latest = aspectFill(CIImage(cvPixelBuffer: buffer))
    }

    // MARK: Output loop

    private func renderTick() {
        let now = CACurrentMediaTime()
        tick += 1

        if now - lastSinkCheck > 2 {
            lastSinkCheck = now
            if sink.deviceVanished() { sink.disconnect() }
            if !sink.isConnected { sink.connect() }
        }

        switch engine.nextFrame(live: latest, last: lastEmitted, now: now) {
        case .hold:
            break
        case let .emit(image):
            if let (bgra, uyvy) = render(image) {
                lastEmitted = CIImage(cvPixelBuffer: bgra)
                lastOutputBuffer = uyvy
            }
        }

        // Always send something so Meet/Zoom never think the camera died.
        if let lastOutputBuffer { sink.send(lastOutputBuffer) }

        if previewEnabled, tick % 3 == 0, let lastEmitted,
           let cg = context.createCGImage(lastEmitted, from: outputRect) {
            onPreview?(cg)
        }

        let newStatus = PipelineStatus(
            mode: engine.mode,
            label: engine.statusLabel(now: now),
            scripted: engine.isScripted,
            sinkConnected: sink.isConnected,
            cameraRunning: cameraRunning)
        if newStatus != status {
            status = newStatus
            onStatus?(newStatus)
        }
    }

    /// Renders to a flat BGRA buffer (kept as the "last frame" for stale-block effects),
    /// then converts to UYVY, the only format OBS's sink accepts.
    private func render(_ image: CIImage) -> (CVPixelBuffer, CVPixelBuffer)? {
        guard let bgraPool, let uyvyPool else { return nil }
        var bgraOut: CVPixelBuffer?
        var uyvyOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bgraPool, &bgraOut)
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, uyvyPool, &uyvyOut)
        guard let bgra = bgraOut, let uyvy = uyvyOut else { return nil }

        context.render(image, to: bgra, bounds: outputRect, colorSpace: renderColorSpace)

        CVPixelBufferLockBaseAddress(bgra, .readOnly)
        CVPixelBufferLockBaseAddress(uyvy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(uyvy, [])
            CVPixelBufferUnlockBaseAddress(bgra, .readOnly)
        }
        var src = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(bgra), height: vImagePixelCount(Self.height),
            width: vImagePixelCount(Self.width), rowBytes: CVPixelBufferGetBytesPerRow(bgra))
        var dst = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(uyvy), height: vImagePixelCount(Self.height),
            width: vImagePixelCount(Self.width), rowBytes: CVPixelBufferGetBytesPerRow(uyvy))
        var bgraToARGB: [UInt8] = [3, 2, 1, 0]
        vImageConvert_ARGB8888To422CbYpCrYp8(&src, &dst, &yuvInfo, &bgraToARGB, vImage_Flags(kvImageNoFlags))

        CVBufferSetAttachment(uyvy, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(uyvy, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(uyvy, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        return (bgra, uyvy)
    }

    /// Scales and center-crops any camera frame to exactly 1280x720.
    private func aspectFill(_ image: CIImage) -> CIImage {
        let e = image.extent
        let scale = max(CGFloat(Self.width) / e.width, CGFloat(Self.height) / e.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - CGFloat(Self.width)) / 2
        let dy = (scaled.extent.height - CGFloat(Self.height)) / 2
        return scaled
            .transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
            .cropped(to: outputRect)
    }

    private static func makePool(format: OSType, minimumCount: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: minimumCount] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ] as CFDictionary,
            &pool)
        return pool
    }
}
