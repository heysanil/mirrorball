// Generates Mirrorball's app icon: a gradient squircle with the same
// "connected nodes" glyph used in the menu bar. Run with: swift tools/make_icon.swift
import AppKit

let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237

    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let top = NSColor(srgbRed: 0.22, green: 0.62, blue: 1.0, alpha: 1)
    let bottom = NSColor(srgbRed: 0.04, green: 0.36, blue: 0.86, alpha: 1)
    let gradient = NSGradient(starting: top, ending: bottom)!
    gradient.draw(in: path, angle: -90)

    // Subtle top highlight for depth.
    let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06), xRadius: radius, yRadius: radius)
    NSColor.white.withAlphaComponent(0.10).setFill()
    highlight.fill()

    let glyphPoint = rect.width * 0.52
    let config = NSImage.SymbolConfiguration(pointSize: glyphPoint, weight: .semibold)
    if let base = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let g = base.size
        let tinted = NSImage(size: g)
        tinted.lockFocus()
        NSColor.white.set()
        let r = NSRect(origin: .zero, size: g)
        base.draw(in: r)
        r.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let drawRect = NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height)
        tinted.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes {
    let data = render(size)
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(size).png")
    try! data.write(to: url)
    print("wrote icon_\(size).png")
}
print("done")
