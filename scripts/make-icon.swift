// Disegna l'icona di Copy8 (quadrato blu #0064E1 con il simbolo "copia") in tutte le misure di un .iconset.
// Uso: swiftc scripts/make-icon.swift -o build/make-icon && build/make-icon build/AppIcon.iconset
import AppKit

guard CommandLine.arguments.count > 1 else {
    print("Uso: make-icon <cartella.iconset>")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(_ pixels: Int) -> Data {
    let side = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Corpo dell'icona secondo la griglia macOS: 824/1024 con raggio continuo.
    let inset = side * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = body.width * 0.225
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.03, color: NSColor(white: 0, alpha: 0.28).cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(NSColor(srgbRed: 0, green: 100 / 255, blue: 225 / 255, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Simbolo "copia" del design system, su griglia 24×24.
    let box = body.width * 0.56
    let unit = box / 24
    let ox = body.midX - box / 2
    let oy = body.midY - box / 2
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * unit, y: oy + (24 - y) * unit) }

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.7 * unit)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let front = CGRect(x: ox + 6 * unit, y: oy + 3 * unit, width: 14 * unit, height: 13 * unit)
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: 2 * unit, cornerHeight: 2 * unit, transform: nil))
    ctx.strokePath()

    let back = CGMutablePath()
    back.move(to: point(16, 8))
    back.addLine(to: point(16, 5))
    back.addArc(tangent1End: point(16, 3), tangent2End: point(14, 3), radius: 2 * unit)
    back.addLine(to: point(5, 3))
    back.addArc(tangent1End: point(3, 3), tangent2End: point(3, 5), radius: 2 * unit)
    back.addLine(to: point(3, 14))
    back.addArc(tangent1End: point(3, 16), tangent2End: point(5, 16), radius: 2 * unit)
    back.addLine(to: point(6, 16))
    ctx.addPath(back)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in sizes {
    try render(pixels).write(to: output.appendingPathComponent(name + ".png"))
}
