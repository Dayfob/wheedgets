// Draws the Wheedgets app icon — a glossy bubble about to pop — and writes
// Resources/AppIcon.icns. Every size is drawn from vectors, not downscaled.
//
//   swift Tools/MakeIcon.swift             writes Resources/AppIcon.icns
//   swift Tools/MakeIcon.swift preview.png also writes a 1024 px preview

import AppKit

/// Design space: the macOS icon grid, 1024 × 1024 with an 824 pt tile.
let designSize: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Hue sweep around a center, drawn as thin wedges (CoreGraphics has no conic gradient).
func conic(_ c: CGContext, center: CGPoint, radius: CGFloat, start: CGFloat, stops: [UInt32], alpha: CGFloat) {
    func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }
    let slices = 360
    for i in 0..<slices {
        let t = CGFloat(i) / CGFloat(slices)
        let position = t * CGFloat(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        let f = position - CGFloat(index)
        let a = components(stops[index]), b = components(stops[index + 1])
        c.setFillColor(CGColor(srgbRed: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: alpha))
        let from = start + t * 2 * .pi
        c.move(to: center)
        c.addArc(center: center, radius: radius, startAngle: from, endAngle: from + 2 * .pi / CGFloat(slices) * 1.5, clockwise: false)
        c.closePath()
        c.fillPath()
    }
}

/// A four-point sparkle with a soft glow.
func sparkle(_ c: CGContext, at p: CGPoint, size s: CGFloat) {
    let pinch = s * 0.14
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x, y: p.y + s))
    path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + pinch, y: p.y + pinch))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x + pinch, y: p.y - pinch))
    path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - pinch, y: p.y - pinch))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x - pinch, y: p.y + pinch))
    c.saveGState()
    c.setShadow(offset: .zero, blur: s * 0.6, color: white(1))
    c.addPath(path)
    c.setFillColor(white(1))
    c.fillPath()
    c.restoreGState()
}

func drawIcon(_ c: CGContext) {
    // Tile: deep indigo with a soft glow behind the bubble.
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
    c.addPath(tilePath)
    c.setFillColor(srgb(0x1E1B4B))
    c.fillPath()
    c.restoreGState()

    let center = CGPoint(x: 512, y: 500)
    c.saveGState()
    c.addPath(tilePath)
    c.clip()
    c.drawLinearGradient(gradient([srgb(0x4F46E5), srgb(0x1E1B4B)], [0, 1]),
                         start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    c.drawRadialGradient(gradient([white(0.16), white(0)], [0, 1]),
                         startCenter: center, startRadius: 0, endCenter: center, endRadius: 420, options: [])
    c.restoreGState()

    // The bubble: slightly wider than tall, stretched to its limit.
    let rx: CGFloat = 300, ry: CGFloat = 286
    let bubble = CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry)
    c.saveGState()
    c.addEllipse(in: bubble)
    c.clip()
    // Clear film, brighter toward the rim.
    c.drawRadialGradient(gradient([white(0.02), white(0.06), white(0.3)], [0, 0.72, 1]),
                         startCenter: CGPoint(x: center.x + 30, y: center.y - 30), startRadius: 0,
                         endCenter: center, endRadius: rx, options: [])
    // Thin-film colors at the rim, fading smoothly inward.
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    conic(c, center: center, radius: rx * 1.1, start: .pi * 0.3,
          stops: [0xFF7AD9, 0xFFE17A, 0x7AFFD4, 0x7AB8FF, 0xC77AFF, 0xFF7AD9], alpha: 0.75)
    c.setBlendMode(.destinationIn)
    c.drawRadialGradient(gradient([white(0), white(0), white(0.35), white(1)], [0, 0.6, 0.85, 1]),
                         startCenter: center, startRadius: 0, endCenter: center, endRadius: rx, options: [])
    c.endTransparencyLayer()
    // One reflection: a soft arc upper left.
    c.setLineCap(.round)
    c.setStrokeColor(white(0.85))
    c.setLineWidth(46)
    c.addArc(center: center, radius: rx * 0.7, startAngle: .pi * 0.62, endAngle: .pi * 0.86, clockwise: false)
    c.strokePath()
    c.restoreGState()

    c.setStrokeColor(white(0.6))
    c.setLineWidth(5)
    c.strokeEllipse(in: bubble.insetBy(dx: 2.5, dy: 2.5))

    // The glint on the stretched rim, right where it will give.
    sparkle(c, at: CGPoint(x: center.x + rx * 0.64, y: center.y + ry * 0.72), size: 78)
}

func render(pixels: Int) -> CGImage {
    let c = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    c.interpolationQuality = .high
    c.scaleBy(x: CGFloat(pixels) / designSize, y: CGFloat(pixels) / designSize)
    drawIcon(c)
    return c.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try writePNG(render(pixels: points), to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try writePNG(render(pixels: points * 2), to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("✓ \(output.path)")

if CommandLine.arguments.count > 1 {
    try writePNG(render(pixels: 1024), to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("✓ \(CommandLine.arguments[1])")
}
