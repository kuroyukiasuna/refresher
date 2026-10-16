// Draws the app icon into an .iconset folder. build-app.sh turns that into AppIcon.icns.
//   make-icon <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's macOS icon grid: an 824-point rounded square centered on a 1024-point canvas.
    let size = CGFloat(pixels)
    let inset = size * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.shadowBlurRadius = size * 0.02
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.86, blue: 0.76, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.40, blue: 0.60, alpha: 1),
    ])!
    gradient.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.36, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let eye = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let eyeSize = eye.size
        eye.draw(in: NSRect(
            x: body.midX - eyeSize.width / 2, y: body.midY - eyeSize.height / 2,
            width: eyeSize.width, height: eyeSize.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try renderIcon(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
