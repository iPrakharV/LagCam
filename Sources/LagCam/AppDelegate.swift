import AppKit

/// Receives lagcam:// URLs (Terminal `open`, Shortcuts, Stream Deck, ...).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var urlHandler: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { Self.urlHandler?($0) }
    }
}
