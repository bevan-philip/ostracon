// Renders the app icon PNGs into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(filePath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // macOS icon grid: ~10% inset, continuous rounded square.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(
        starting: NSColor(srgbRed: 0.91, green: 0.36, blue: 0.29, alpha: 1),
        ending: NSColor(srgbRed: 0.80, green: 0.25, blue: 0.20, alpha: 1)
    )?.draw(in: path, angle: -90)

    // A shard-like circle with a tick: an ostracon was a pottery shard used for voting.
    let circle = NSBezierPath(ovalIn: tile.insetBy(dx: s * 0.17, dy: s * 0.17))
    circle.lineWidth = s * 0.045
    NSColor.white.setStroke()
    circle.stroke()

    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: s * 0.39, y: s * 0.50))
    tick.line(to: NSPoint(x: s * 0.47, y: s * 0.42))
    tick.line(to: NSPoint(x: s * 0.62, y: s * 0.59))
    tick.lineWidth = s * 0.05
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    tick.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appending(path: "icon_\(base)x\(base)@2x.png"))
}
