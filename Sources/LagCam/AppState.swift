import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status = PipelineStatus()
    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var cameraDenied = false
    @Published var previewImage: CGImage?

    @Published var selectedCameraID: String? {
        didSet {
            guard selectedCameraID != oldValue else { return }
            UserDefaults.standard.set(selectedCameraID, forKey: "cameraID")
            pipeline.selectCamera(selectedCameraID)
        }
    }

    @Published var intensity: Double {
        didSet {
            UserDefaults.standard.set(intensity, forKey: "intensity")
            pipeline.setIntensity(intensity)
        }
    }

    @Published var disconnectDuration: Double {
        didSet { UserDefaults.standard.set(disconnectDuration, forKey: "disconnectDuration") }
    }

    private let pipeline = Pipeline()
    private let hotkeys = HotkeyManager()
    private var previewWindow: NSWindow?

    #if SCREENSHOTS
    /// Only compiled by scripts/make-screenshots.sh: fake status for README images.
    init(demoStatus: PipelineStatus, cameras: [CameraInfo]) {
        intensity = 0.6
        disconnectDuration = 30
        status = demoStatus
        self.cameras = cameras
        selectedCameraID = cameras.first?.id
    }
    #endif

    init() {
        let defaults = UserDefaults.standard
        intensity = defaults.object(forKey: "intensity") as? Double ?? 0.6
        disconnectDuration = defaults.object(forKey: "disconnectDuration") as? Double ?? 30
        selectedCameraID = defaults.string(forKey: "cameraID")

        pipeline.setIntensity(intensity)
        pipeline.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.status = status }
        }
        pipeline.onPreview = { [weak self] image in
            DispatchQueue.main.async { self?.previewImage = image }
        }

        registerHotkeys()
        requestCameraAndStart()
        AppDelegate.urlHandler = { [weak self] url in self?.handle(url) }
    }

    var menuBarSymbol: String {
        if status.scripted { return "wifi.exclamationmark" }
        return status.mode == .normal ? "video" : status.mode.symbol
    }

    // MARK: Actions

    func setMode(_ mode: Mode) { pipeline.setMode(mode) }
    func fakeDisconnect() { pipeline.startDisconnect(duration: disconnectDuration) }
    func reconnect() { pipeline.startReconnect() }

    /// lagcam://normal, laggy, bad, frozen, disconnect[?seconds=30], reconnect
    func handle(_ url: URL) {
        guard url.scheme == "lagcam" else { return }
        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let mode = Mode(rawValue: command) {
            setMode(mode)
        } else if command == "disconnect" {
            let seconds = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "seconds" })?.value.flatMap(Double.init)
            pipeline.startDisconnect(duration: seconds ?? disconnectDuration)
        } else if command == "reconnect" {
            reconnect()
        }
    }

    func refreshCameras() {
        cameras = CameraCapture.availableCameras()
        if selectedCameraID == nil || !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = cameras.first?.id
        }
    }

    func togglePreview() {
        if let previewWindow, previewWindow.isVisible {
            previewWindow.close()
            return
        }
        let window = previewWindow ?? makePreviewWindow()
        previewWindow = window
        pipeline.setPreviewEnabled(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func quit() {
        pipeline.stop()
        NSApp.terminate(nil)
    }

    // MARK: Setup

    private func requestCameraAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startPipeline()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.startPipeline() } else { self.cameraDenied = true }
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func startPipeline() {
        refreshCameras()
        pipeline.start(cameraID: selectedCameraID)
    }

    private func registerHotkeys() {
        hotkeys.register(.one) { [weak self] in self?.setMode(.normal) }
        hotkeys.register(.two) { [weak self] in self?.setMode(.laggy) }
        hotkeys.register(.three) { [weak self] in self?.setMode(.bad) }
        hotkeys.register(.four) { [weak self] in self?.setMode(.frozen) }
        hotkeys.register(.d) { [weak self] in self?.fakeDisconnect() }
        hotkeys.register(.r) { [weak self] in self?.reconnect() }
    }

    private func makePreviewWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "LagCam Preview (what others see)"
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.contentView = NSHostingView(rootView: PreviewView().environmentObject(self))
        window.center()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pipeline.setPreviewEnabled(false)
                self?.previewImage = nil
            }
        }
        return window
    }
}

struct PreviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.black
            if let image = state.previewImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(minWidth: 320, minHeight: 180)
    }
}
