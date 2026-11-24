// 앱 아이콘(AppIcon.icns)을 코드로 그린다.
// 사용법: swift scripts/make-icon.swift  → Resources/AppIcon.icns 생성
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// 말풍선: 둥근 사각형 + 아래쪽 꼬리.
func bubble(_ r: NSRect, radius: CGFloat, tailLeft: Bool) -> NSBezierPath {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    let tail = NSBezierPath()
    let w = r.width * 0.16
    let x = tailLeft ? r.minX + r.width * 0.16 : r.maxX - r.width * 0.16 - w
    tail.move(to: NSPoint(x: x, y: r.minY + 2))
    tail.line(to: NSPoint(x: tailLeft ? x - w * 0.35 : x + w * 1.35, y: r.minY - w * 0.9))
    tail.line(to: NSPoint(x: x + w, y: r.minY + 2))
    tail.close()
    p.append(tail)
    return p
}

func textLines(in r: NSRect, widths: [CGFloat], color c: NSColor) {
    let h = r.height / (CGFloat(widths.count) * 2 - 1)
    c.setFill()
    for (i, w) in widths.enumerated() {
        let y = r.maxY - h - CGFloat(i) * h * 2
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: y, width: r.width * w, height: h),
                     xRadius: h / 2, yRadius: h / 2).fill()
    }
}

func draw(size s: CGFloat) {
    let k = s / 1024
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * k, y: y * k, width: w * k, height: h * k)
    }

    // 바탕: macOS 아이콘 격자(1024 중 824)에 맞춘 둥근 사각형.
    let plate = R(100, 100, 824, 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.3)
    shadow.shadowBlurRadius = 20 * k
    shadow.shadowOffset = NSSize(width: 0, height: -8 * k)
    shadow.set()
    color(0x2B2D6E).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x5B5FEF), color(0x2E2A8A)])!.draw(in: platePath, angle: -90)

    // 뒤쪽 말풍선(사용자): 반투명 흰색, 오른쪽 위.
    let back = R(330, 520, 470, 290)
    color(0xFFFFFF, 0.28).setFill()
    bubble(back, radius: 70 * k, tailLeft: true).fill()
    textLines(in: back.insetBy(dx: 70 * k, dy: 85 * k), widths: [1, 0.6], color: color(0xFFFFFF, 0.55))

    // 앞쪽 말풍선(AI): 흰색, 왼쪽 아래.
    let front = R(205, 250, 520, 320)
    NSGraphicsContext.saveGraphicsState()
    let s2 = NSShadow()
    s2.shadowColor = color(0x000000, 0.25)
    s2.shadowBlurRadius = 24 * k
    s2.shadowOffset = NSSize(width: 0, height: -10 * k)
    s2.set()
    color(0xFFFFFF).setFill()
    bubble(front, radius: 76 * k, tailLeft: true).fill()
    NSGraphicsContext.restoreGraphicsState()
    textLines(in: front.insetBy(dx: 78 * k, dy: 88 * k), widths: [1, 0.82, 0.5], color: color(0x4B4FD6, 0.85))

    // 실행 중인 세션 표시: 초록 점.
    let dot = R(640, 485, 120, 120)
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: dot.insetBy(dx: -14 * k, dy: -14 * k)).fill()
    color(0x34C759).setFill()
    NSBezierPath(ovalIn: dot).fill()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = outDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try png(pixels: 1024).write(to: fm.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print(task.terminationStatus == 0 ? "생성: \(out.path)" : "iconutil 실패")
