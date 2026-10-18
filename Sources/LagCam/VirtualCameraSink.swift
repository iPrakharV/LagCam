import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

/// Pushes frames into the OBS Virtual Camera's CoreMediaIO sink stream.
///
/// OBS (30+) ships a signed camera extension with two streams: a source stream that
/// apps like Meet/Zoom read, and a sink stream that OBS writes to. Any process can
/// write UYVY frames into the sink, so we can reuse the driver without OBS running.
/// Approach adapted from pyvirtualcam's native_macos_obs_cmioextension backend.
final class VirtualCameraSink {
    /// Device UID hard-coded in OBS's camera extension (OBSCameraProviderSource.swift).
    static let obsDeviceUID = "7626645E-4425-469E-9D8B-97E0FA59AC75"
    static let obsDeviceName = "OBS Virtual Camera"

    private(set) var isConnected = false
    private var deviceID: CMIOObjectID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private var formatDescription: CMVideoFormatDescription?

    deinit { disconnect() }

    /// Finds the OBS device and starts its sink stream. Safe to call repeatedly.
    @discardableResult
    func connect() -> Bool {
        if isConnected { return true }
        guard let device = Self.findOBSDevice() else { return false }

        let streams: [CMIOStreamID] = Self.getArray(device, kCMIODevicePropertyStreams)
        // There is no stream UID property; OBS's sink is always the second stream.
        guard streams.count >= 2 else { return false }
        let stream = streams[1]

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &unmanagedQueue)
        guard status == noErr, let q = unmanagedQueue?.takeRetainedValue() else { return false }

        guard CMIODeviceStartStream(device, stream) == noErr else { return false }

        deviceID = device
        streamID = stream
        queue = q
        formatDescription = nil
        isConnected = true
        return true
    }

    func disconnect() {
        if isConnected {
            CMIODeviceStopStream(deviceID, streamID)
        }
        isConnected = false
        queue = nil
        formatDescription = nil
        deviceID = 0
        streamID = 0
    }

    /// True if the device we are streaming to has disappeared (extension removed/updated).
    func deviceVanished() -> Bool {
        guard isConnected else { return false }
        return Self.findOBSDevice() != deviceID
    }

    /// Enqueues a UYVY (kCVPixelFormatType_422YpCbCr8) pixel buffer.
    func send(_ pixelBuffer: CVPixelBuffer) {
        guard isConnected, let queue else { return }

        // If nobody is consuming (no app has the camera open) the queue fills up; drop frames.
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) { return }

        if formatDescription == nil
            || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            var fd: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
            formatDescription = fd
        }
        guard let formatDescription else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: CMTimeValue(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription,
            sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { return }

        // Ownership of the +1 reference passes to the queue's consumer (the extension).
        let element = Unmanaged.passRetained(sampleBuffer).toOpaque()
        if CMSimpleQueueEnqueue(queue, element: element) != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(element).release()
        }
    }

    // MARK: - CoreMediaIO helpers

    static func isOBSInstalled() -> Bool { findOBSDevice() != nil }

    private static func findOBSDevice() -> CMIOObjectID? {
        let devices: [CMIOObjectID] = getArray(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
        for device in devices {
            if getString(device, kCMIODevicePropertyDeviceUID) == obsDeviceUID { return device }
        }
        for device in devices {
            if getString(device, kCMIOObjectPropertyName) == obsDeviceName { return device }
        }
        return nil
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func getArray<T: FixedWidthInteger>(_ object: CMIOObjectID, _ selector: Int) -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [T](repeating: 0, count: Int(size) / MemoryLayout<T>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &items) == noErr else { return [] }
        return Array(items.prefix(Int(used) / MemoryLayout<T>.size))
    }

    private static func getString(_ object: CMIOObjectID, _ selector: Int) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
