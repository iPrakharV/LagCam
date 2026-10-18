import CoreImage
import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case normal, laggy, bad, frozen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .laggy: return "Laggy"
        case .bad: return "Bad connection"
        case .frozen: return "Frozen"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "video"
        case .laggy: return "tortoise"
        case .bad: return "wifi.exclamationmark"
        case .frozen: return "snowflake"
        }
    }
}

/// What the output loop should do on this tick.
enum FrameDecision {
    /// Re-send the previous output frame (the picture appears stuck).
    case hold
    /// Send a new frame.
    case emit(CIImage)
}

/// Decides, 30 times a second, whether the viewer gets a fresh frame, a stuck frame,
/// or a degraded frame. Only used from the pipeline queue.
final class EffectsEngine {
    private enum Script {
        case none
        case disconnect(start: Double, duration: Double)
        case reconnect(start: Double)
    }

    private(set) var mode: Mode = .normal
    /// 0...1, scales how bad the manual modes (and scripted ramps) look.
    var intensity: Double = 0.6

    private var script: Script = .none
    private var holdUntil: Double = 0
    private var blockRects: [CGRect] = []
    private var staleRects: [CGRect] = []
    private var blocksUntil: Double = 0

    // MARK: Commands

    func setMode(_ newMode: Mode) {
        mode = newMode
        script = .none
        holdUntil = 0
    }

    func startDisconnect(now: Double, duration: Double) {
        mode = .normal
        script = .disconnect(start: now, duration: duration)
    }

    func startReconnect(now: Double) {
        script = .reconnect(start: now)
    }

    // MARK: Status

    /// Human readable label for the menu, e.g. "Disconnecting… 40%".
    func statusLabel(now: Double) -> String {
        switch script {
        case .none:
            return mode.title
        case let .disconnect(start, duration):
            let pct = Int(min(1, max(0, (now - start) / duration)) * 100)
            return "Disconnecting… \(pct)%"
        case .reconnect:
            return "Reconnecting…"
        }
    }

    var isScripted: Bool {
        if case .none = script { return false }
        return true
    }

    // MARK: Frame decision

    func nextFrame(live: CIImage?, last: CIImage?, now: Double) -> FrameDecision {
        let (phase, severity) = currentPhase(now: now)

        guard let live else {
            // No camera frame yet: keep showing whatever we showed last.
            return last == nil ? .emit(Self.black) : .hold
        }

        switch phase {
        case .normal:
            return .emit(live)

        case .frozen:
            return last == nil ? .emit(live) : .hold

        case .laggy:
            if now < holdUntil { return .hold }
            scheduleNextFrame(
                now: now,
                fps: lerp(30, 3, severity),
                hiccupChance: lerp(0.04, 0.2, severity),
                hiccupLength: lerp(0.25, 0.6, severity)...lerp(0.7, 2.2, severity))
            return .emit(live)

        case .bad:
            if now < holdUntil { return .hold }
            scheduleNextFrame(
                now: now,
                fps: lerp(12, 3, severity),
                hiccupChance: lerp(0.03, 0.14, severity),
                hiccupLength: lerp(0.2, 0.4, severity)...lerp(0.5, 1.4, severity))
            return .emit(degrade(live, last: last, severity: severity, now: now))
        }
    }

    // MARK: Internals

    /// The effective mode + severity right now, advancing any scripted sequence.
    private func currentPhase(now: Double) -> (Mode, Double) {
        switch script {
        case .none:
            return (mode, intensity)

        case let .disconnect(start, duration):
            let p = (now - start) / duration
            let scale = 0.4 + 0.6 * intensity
            switch p {
            case ..<0.25: return (.laggy, lerp(0.0, 0.4, p / 0.25) * scale)
            case ..<0.6: return (.laggy, lerp(0.4, 1.0, (p - 0.25) / 0.35) * scale)
            case ..<1.0: return (.bad, lerp(0.35, 1.0, (p - 0.6) / 0.4) * scale)
            default:
                script = .none
                mode = .frozen
                return (.frozen, 1)
            }

        case let .reconnect(start):
            let t = now - start
            switch t {
            case ..<1.2: return (.frozen, 1)
            case ..<4.5: return (.bad, lerp(0.8, 0.1, (t - 1.2) / 3.3))
            default:
                script = .none
                mode = .normal
                return (.normal, 0)
            }
        }
    }

    private func scheduleNextFrame(
        now: Double, fps: Double, hiccupChance: Double, hiccupLength: ClosedRange<Double>
    ) {
        var interval = 1 / fps
        if Double.random(in: 0...1) < hiccupChance {
            interval = Double.random(in: hiccupLength)
        }
        holdUntil = now + interval * Double.random(in: 0.7...1.3)
    }

    /// Low-res, blocky, smeared "bad Wi-Fi" look.
    private func degrade(_ image: CIImage, last: CIImage?, severity: Double, now: Double) -> CIImage {
        let extent = image.extent

        // 1. Drop resolution: scale down, then back up with smooth filtering (codec blur).
        // Lanczos (not an affine transform) so Core Image can't fold down+up into a no-op.
        let factor = lerp(0.25, 0.04, severity)
        let small = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: factor,
            kCIInputAspectRatioKey: 1.0,
        ])
        var result = small
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / small.extent.width, y: extent.height / small.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)

        // 2. Wash out colors a little.
        result = result.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: lerp(0.95, 0.7, severity),
            kCIInputContrastKey: lerp(0.98, 0.9, severity),
        ])

        // 3. Macroblocks and stale regions that change every few hundred ms.
        if now >= blocksUntil {
            blocksUntil = now + Double.random(in: 0.15...0.5)
            blockRects = randomBlockRects(in: extent, count: Int(lerp(1, 7, severity)))
            staleRects = randomBlockRects(in: extent, count: Int(lerp(0, 4, severity)))
        }

        let pixellated = image.applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: lerp(16, 48, severity),
            kCIInputCenterKey: CIVector(x: 0, y: 0),
        ])
        for rect in blockRects {
            result = pixellated.cropped(to: rect).composited(over: result)
        }

        // Stale blocks: parts of the previous frame stay on screen, like lost packets.
        if let last {
            for rect in staleRects {
                result = last.cropped(to: rect).composited(over: result)
            }
        }

        return result.cropped(to: extent)
    }

    private func randomBlockRects(in extent: CGRect, count: Int) -> [CGRect] {
        let block: CGFloat = 32
        let cols = Int(extent.width / block)
        let rows = Int(extent.height / block)
        guard cols > 4, rows > 4 else { return [] }
        return (0..<count).map { _ in
            let w = Int.random(in: 2...min(10, cols))
            let h = Int.random(in: 2...min(6, rows))
            let x = Int.random(in: 0...(cols - w))
            let y = Int.random(in: 0...(rows - h))
            return CGRect(
                x: extent.minX + CGFloat(x) * block, y: extent.minY + CGFloat(y) * block,
                width: CGFloat(w) * block, height: CGFloat(h) * block)
        }
    }

    private static let black = CIImage(color: .black)
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(1, max(0, t))
}
