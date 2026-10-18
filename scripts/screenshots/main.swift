// Generates the images in docs/images/ for the README.
// Uses the app's real EffectsEngine and MenuBarView, drawn on a synthetic demo scene.
// Run via scripts/make-screenshots.sh.
import AppKit
import CoreImage
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let W = 1280, H = 720
let frameRect = CGRect(x: 0, y: 0, width: W, height: H)
let ciContext = CIContext()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Drawing helpers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}

func drawText(
    _ ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold,
    color c: NSColor = .white, centered: Bool = false
) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    var p = point
    if centered { p.x -= str.size().width / 2 }
    str.draw(at: p)
    NSGraphicsContext.restoreGraphicsState()
}

func roundedRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

// MARK: - Demo scene: a flat-illustration "home office" video-call frame

/// `t` animates the person (head bob, waving hand) so frame holds are visible.
func drawScene(t: Double) -> CGImage {
    let ctx = makeContext(W, H)
    let h = CGFloat(H)

    // Wall
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: sRGB, colors: [color(0xEFE6DA), color(0xDCCDBB)] as CFArray, locations: [0, 1])!,
        start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // Window with sky, sun and hills
    let win = CGRect(x: 90, y: 300, width: 300, height: 300)
    roundedRect(ctx, win.insetBy(dx: -14, dy: -14), 10, fill: color(0xFFFFFF))
    ctx.saveGState()
    ctx.clip(to: win)
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: sRGB, colors: [color(0x7EC8F2), color(0xD4EEFB)] as CFArray, locations: [0, 1])!,
        start: CGPoint(x: 0, y: win.maxY), end: CGPoint(x: 0, y: win.minY), options: [])
    ctx.setFillColor(color(0xFFD45C))
    ctx.fillEllipse(in: CGRect(x: 290, y: 500, width: 60, height: 60))
    ctx.setFillColor(color(0x8CC084))
    ctx.fillEllipse(in: CGRect(x: 40, y: 230, width: 260, height: 150))
    ctx.setFillColor(color(0x6FAE6A))
    ctx.fillEllipse(in: CGRect(x: 200, y: 220, width: 280, height: 140))
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fill(CGRect(x: win.midX - 6, y: win.minY, width: 12, height: win.height))
    ctx.fill(CGRect(x: win.minX, y: win.midY - 6, width: win.width, height: 12))

    // Bookshelf
    let shelfX: CGFloat = 900
    ctx.setFillColor(color(0x9B7653))
    ctx.fill(CGRect(x: shelfX, y: 180, width: 300, height: 440))
    ctx.setFillColor(color(0x7A5C40))
    let bookColors: [UInt32] = [0xE07A5F, 0x3D405B, 0x81B29A, 0xF2CC8F, 0x5E81AC, 0xBF616A, 0xA3BE8C, 0xEBCB8B]
    for row in 0..<3 {
        let y = 200 + CGFloat(row) * 140
        ctx.setFillColor(color(0x7A5C40))
        ctx.fill(CGRect(x: shelfX + 12, y: y, width: 276, height: 120))
        var x = shelfX + 22
        var i = row * 3
        while x < shelfX + 250 {
            let bw = CGFloat(18 + (i * 7) % 16)
            let bh = CGFloat(80 + (i * 13) % 34)
            ctx.setFillColor(color(bookColors[i % bookColors.count]))
            ctx.fill(CGRect(x: x, y: y, width: bw, height: bh))
            x += bw + 4
            i += 1
        }
    }

    // Plant
    ctx.setFillColor(color(0xC8693F))
    ctx.fill(CGRect(x: 520, y: 330, width: 70, height: 70))
    ctx.setFillColor(color(0x4F9D69))
    for k in 0..<7 {
        let a = Double(k) / 6 * .pi
        ctx.saveGState()
        ctx.translateBy(x: 555, y: 400)
        ctx.rotate(by: CGFloat(a - .pi / 2) * 0.9)
        ctx.fillEllipse(in: CGRect(x: -14, y: 0, width: 28, height: 95))
        ctx.restoreGState()
    }

    // Person
    let bob = CGFloat(sin(t * 2.1) * 10)
    let cx: CGFloat = 640 + CGFloat(sin(t * 1.3) * 18)

    // Shoulders / shirt
    ctx.setFillColor(color(0x3B6EA5))
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: cx - 230, y: -120, width: 460, height: 360),
        cornerWidth: 170, cornerHeight: 170, transform: nil))
    ctx.fillPath()
    // Neck
    ctx.setFillColor(color(0xD99B70))
    ctx.fill(CGRect(x: cx - 38, y: 200, width: 76, height: 80))
    // Head
    let head = CGRect(x: cx - 105, y: 250 + bob, width: 210, height: 240)
    ctx.setFillColor(color(0xE8B48A))
    ctx.fillEllipse(in: head)
    // Hair
    ctx.setFillColor(color(0x2E2A28))
    ctx.saveGState()
    ctx.clip(to: CGRect(x: head.minX - 10, y: head.midY + 35, width: head.width + 20, height: head.height))
    ctx.fillEllipse(in: head.insetBy(dx: -10, dy: -12))
    ctx.restoreGState()
    // Headphones
    ctx.setStrokeColor(color(0x222222))
    ctx.setLineWidth(16)
    ctx.addArc(center: CGPoint(x: head.midX, y: head.midY + 10), radius: 122, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(color(0x222222))
    roundedRect(ctx, CGRect(x: head.minX - 26, y: head.midY - 30, width: 40, height: 80), 16, fill: color(0x222222))
    roundedRect(ctx, CGRect(x: head.maxX - 14, y: head.midY - 30, width: 40, height: 80), 16, fill: color(0x222222))
    // Face
    let blink = (t.truncatingRemainder(dividingBy: 3.0)) > 2.85
    ctx.setFillColor(color(0x2E2A28))
    if blink {
        ctx.fill(CGRect(x: head.midX - 52, y: head.midY - 2, width: 28, height: 5))
        ctx.fill(CGRect(x: head.midX + 24, y: head.midY - 2, width: 28, height: 5))
    } else {
        ctx.fillEllipse(in: CGRect(x: head.midX - 48, y: head.midY - 10, width: 20, height: 24))
        ctx.fillEllipse(in: CGRect(x: head.midX + 28, y: head.midY - 10, width: 20, height: 24))
    }
    ctx.setStrokeColor(color(0x9C4A3A))
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: head.midX, y: head.midY - 30), radius: 34, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
    ctx.strokePath()

    // Waving hand
    let wave = CGFloat(sin(t * 6) * 0.35)
    ctx.saveGState()
    ctx.translateBy(x: cx + 250, y: 60)
    ctx.rotate(by: -0.25 + wave)
    ctx.setFillColor(color(0x3B6EA5))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -36, y: 0, width: 72, height: 230), cornerWidth: 36, cornerHeight: 36, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0xE8B48A))
    ctx.fillEllipse(in: CGRect(x: -42, y: 215, width: 84, height: 96))
    ctx.restoreGState()

    // Name tag like a meeting tile
    roundedRect(ctx, CGRect(x: 24, y: 24, width: 150, height: 44), 10, fill: color(0x000000, 0.45))
    drawText(ctx, "Alex", at: CGPoint(x: 40, y: 33), size: 22, weight: .medium)

    return ctx.makeImage()!
}

func render(_ image: CIImage) -> CGImage {
    ciContext.createCGImage(image, from: frameRect, format: .RGBA8, colorSpace: sRGB)!
}

// MARK: - Effect frames via the real EffectsEngine

/// Runs the engine for `seconds` of simulated 30 fps video and returns every output frame.
func simulate(_ setup: (EffectsEngine) -> Void, seconds: Double, startT: Double = 0) -> [CGImage] {
    let engine = EffectsEngine()
    setup(engine)
    var last: CIImage?
    var lastCG: CGImage?
    var frames: [CGImage] = []
    for i in 0..<Int(seconds * 30) {
        let now = Double(i) / 30
        let live = CIImage(cgImage: drawScene(t: startT + now))
        switch engine.nextFrame(live: live, last: last, now: now) {
        case .hold:
            break
        case let .emit(img):
            lastCG = render(img)
            last = CIImage(cgImage: lastCG!)
        }
        frames.append(lastCG!)
    }
    return frames
}

let normalFrame = drawScene(t: 0.6)
savePNG(normalFrame, "scene-normal.png")

srand48(7)
let badFrames = simulate({ $0.intensity = 0.85; $0.setMode(.bad) }, seconds: 3, startT: 0.6)
let badFrame = badFrames[badFrames.count - 1]
savePNG(badFrame, "scene-bad.png")

let laggyFrames = simulate({ $0.intensity = 0.6; $0.setMode(.laggy) }, seconds: 6, startT: 0.6)

// Frozen: a mid-blink, mid-wave degraded frame held on screen.
let frozenSource = simulate({ $0.intensity = 0.5; $0.setMode(.bad) }, seconds: 1.0, startT: 2.2)
let frozenFrame: CGImage = {
    let ctx = makeContext(W, H)
    ctx.draw(frozenSource.last!, in: frameRect)
    return ctx.makeImage()!
}()
savePNG(frozenFrame, "scene-frozen.png")

// MARK: - Composite images

func drawImage(_ ctx: CGContext, _ img: CGImage, in r: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.draw(img, in: r)
    ctx.restoreGState()
}

func badge(_ ctx: CGContext, _ text: String, at p: CGPoint, fill: CGColor, size: CGFloat = 22) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .bold)]
    let w = NSAttributedString(string: text, attributes: attrs).size().width
    roundedRect(ctx, CGRect(x: p.x, y: p.y, width: w + 28, height: size + 18), (size + 18) / 2, fill: fill)
    drawText(ctx, text, at: CGPoint(x: p.x + 14, y: p.y + 7), size: size, weight: .bold)
}

// Hero banner: Normal → Bad connection → Frozen
do {
    let bw = 2400, bh = 900
    let ctx = makeContext(bw, bh)
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: sRGB, colors: [color(0x0F172A), color(0x1E1B4B)] as CFArray, locations: [0, 1])!,
        start: .zero, end: CGPoint(x: CGFloat(bw), y: CGFloat(bh)), options: [])
    drawText(ctx, "LagCam", at: CGPoint(x: CGFloat(bw) / 2, y: 740), size: 96, weight: .heavy, centered: true)
    drawText(
        ctx, "Fake a bad connection on Google Meet & Zoom — one click, totally believable.",
        at: CGPoint(x: CGFloat(bw) / 2, y: 670), size: 38, weight: .regular,
        color: NSColor(white: 1, alpha: 0.75), centered: true)

    let panels: [(CGImage, String, CGColor)] = [
        (normalFrame, "Normal", color(0x16A34A)),
        (badFrame, "Bad connection", color(0xEA580C)),
        (frozenFrame, "Frozen", color(0x2563EB)),
    ]
    let pw: CGFloat = 700, ph: CGFloat = pw * 9 / 16, gap: CGFloat = 60
    let startX = (CGFloat(bw) - (pw * 3 + gap * 2)) / 2
    for (i, (img, label, c)) in panels.enumerated() {
        let r = CGRect(x: startX + CGFloat(i) * (pw + gap), y: 160, width: pw, height: ph)
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: color(0x000000, 0.5))
        roundedRect(ctx, r, 24, fill: color(0x000000))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        drawImage(ctx, img, in: r, radius: 24)
        badge(ctx, label, at: CGPoint(x: r.minX + 20, y: r.maxY - 64), fill: c)
        if i < 2 {
            drawText(ctx, "→", at: CGPoint(x: r.maxX + gap / 2, y: r.midY - 34), size: 56, weight: .bold,
                     color: NSColor(white: 1, alpha: 0.6), centered: true)
        }
    }
    drawText(ctx, "Works with any app that lets you pick a camera  ·  Free & open source  ·  macOS 14+",
             at: CGPoint(x: CGFloat(bw) / 2, y: 70), size: 30, weight: .medium,
             color: NSColor(white: 1, alpha: 0.55), centered: true)
    savePNG(ctx.makeImage()!, "hero.png")
}

// Filmstrip: what viewers receive each frame, normal vs laggy.
do {
    let count = 12
    let tw: CGFloat = 192, th: CGFloat = 108, gap: CGFloat = 8
    let labelW: CGFloat = 180
    let fw = Int(labelW + CGFloat(count) * (tw + gap) + 40), fh = 420
    let ctx = makeContext(fw, fh)
    ctx.setFillColor(color(0x0F172A))
    ctx.fill(CGRect(x: 0, y: 0, width: fw, height: fh))
    let normal = (0..<count).map { drawScene(t: 0.6 + Double($0 * 3) / 30) }
    // Pick the stretch of the laggy run with the most realistic mix of new and repeated frames.
    func sameCount(_ start: Int) -> Int {
        (1..<count).filter { laggyFrames[start + $0 * 3] === laggyFrames[start + ($0 - 1) * 3] }.count
    }
    let best = stride(from: 0, to: laggyFrames.count - count * 3, by: 1)
        .min(by: { abs(sameCount($0) - 6) < abs(sameCount($1) - 6) })!
    let laggy = (0..<count).map { laggyFrames[best + $0 * 3] }
    let rows: [(String, [CGImage], CGColor)] = [
        ("Normal", normal, color(0x16A34A)), ("Laggy", laggy, color(0xEA580C)),
    ]
    for (ri, (name, frames, c)) in rows.enumerated() {
        let y = CGFloat(fh) - 90 - CGFloat(ri + 1) * th - CGFloat(ri) * 60
        drawText(ctx, name, at: CGPoint(x: 24, y: y + th / 2 - 14), size: 28, weight: .bold,
                 color: NSColor(cgColor: c)!)
        for (i, img) in frames.enumerated() {
            let r = CGRect(x: labelW + CGFloat(i) * (tw + gap), y: y, width: tw, height: th)
            drawImage(ctx, img, in: r, radius: 8)
            if i > 0, img === frames[i - 1] {
                roundedRect(ctx, CGRect(x: r.minX + 6, y: r.minY + 6, width: 64, height: 26), 13, fill: color(0xEA580C))
                drawText(ctx, "SAME", at: CGPoint(x: r.minX + 13, y: r.minY + 9), size: 15, weight: .heavy)
            }
        }
    }
    drawText(ctx, "Every 100 ms of video, as your viewers receive it →",
             at: CGPoint(x: labelW, y: CGFloat(fh) - 56), size: 22, weight: .medium,
             color: NSColor(white: 1, alpha: 0.7))
    savePNG(ctx.makeImage()!, "filmstrip.png")
}

// MARK: - Menu bar UI screenshots (the real SwiftUI view)

@MainActor
func renderMenu(dark: Bool, status: PipelineStatus, name: String, warn: Bool = false) {
    let state = AppState(
        demoStatus: status,
        cameras: [CameraInfo(id: "builtin", name: "MacBook Pro Camera")])
    let view = MenuBarView().environmentObject(state)
    let hosting = NSHostingView(rootView: view)
    hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let size = hosting.fittingSize
    let window = KeyWindow(contentRect: CGRect(x: -10000, y: -10000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = hosting.appearance
    window.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    hosting.layoutSubtreeIfNeeded()

    let scale: CGFloat = 2
    let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let content = rep.cgImage!

    // Put it on a rounded "popover" card with a soft shadow and padding.
    let pad: CGFloat = 60
    let cw = CGFloat(content.width), ch = CGFloat(content.height)
    let ctx = makeContext(Int(cw + pad * 2), Int(ch + pad * 2))
    let r = CGRect(x: pad, y: pad, width: cw, height: ch)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: color(0x000000, dark ? 0.6 : 0.25))
    roundedRect(ctx, r, 14 * scale, fill: dark ? color(0x2A2A2A) : color(0xF7F7F7))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    drawImage(ctx, content, in: r, radius: 14 * scale)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14 * scale, cornerHeight: 14 * scale, transform: nil))
    ctx.setStrokeColor(dark ? color(0xFFFFFF, 0.12) : color(0x000000, 0.1))
    ctx.setLineWidth(2)
    ctx.strokePath()
    savePNG(ctx.makeImage()!, name)
    window.orderOut(nil)
}

/// Borderless windows can't become key by default; key windows draw controls in their active colors.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let ok = PipelineStatus(mode: .normal, label: "Normal", scripted: false, sinkConnected: true, cameraRunning: true)
    renderMenu(dark: true, status: ok, name: "menu-dark.png")
    renderMenu(dark: false, status: ok, name: "menu-light.png")
    let dis = PipelineStatus(mode: .normal, label: "Disconnecting… 64%", scripted: true, sinkConnected: true, cameraRunning: true)
    renderMenu(dark: true, status: dis, name: "menu-disconnecting-dark.png")
    let missing = PipelineStatus(mode: .normal, label: "Normal", scripted: false, sinkConnected: false, cameraRunning: true)
    renderMenu(dark: true, status: missing, name: "menu-obs-missing-dark.png")
}
