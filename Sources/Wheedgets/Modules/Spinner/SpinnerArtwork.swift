import AppKit
import WheedgetsCore

/// Draws the spinner as a matte object in an iPhone finish: flat color, no
/// highlights, with only a soft shadow and a hairline to set it off from
/// whatever is behind it. Bearings and the center cap are quiet, slightly
/// darker tones of the same finish.
///
/// Rendered once per size, color and appearance, then only rotated.
@MainActor
enum SpinnerArtwork {
    struct Images {
        /// The spinner itself, without its shadow.
        let sharp: CGImage
        /// A rotational smear, shown at speeds where the eye sees a blurred disc.
        let smear: CGImage
        /// The spinner's blurred silhouette. It turns with the spinner but is
        /// drawn offset downward on screen, so the light never moves; baked
        /// into the turning image, the shadow would circle it once a turn.
        let shadow: CGImage
    }

    /// How far the shadow falls below the spinner, as a fraction of its size.
    static let shadowDrop: CGFloat = 0.02

    static func render(color: SpinnerColor, size: CGFloat, scale: CGFloat, appearance: NSAppearance) -> Images? {
        // Dynamic system colors resolve against the appearance being drawn.
        var images: Images?
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tint = Self.tint(for: color)
            guard let sharp = draw(size: size, scale: scale, {
                drawSpinner(in: $0, size: size, tint: tint, isDark: isDark)
            }), let shadow = draw(size: size, scale: scale, {
                drawShadow(in: $0, size: size, scale: scale, isDark: isDark)
            }) else { return }
            let smear = draw(size: size, scale: scale) { context in
                // Many faint copies around the circle blend into a spinning blur.
                let copies = 120
                let rect = CGRect(x: 0, y: 0, width: size, height: size)
                context.setAlpha(3 / CGFloat(copies))
                for index in 0..<copies {
                    context.saveGState()
                    context.translateBy(x: size / 2, y: size / 2)
                    context.rotate(by: CGFloat(index) * 2 * .pi / CGFloat(copies))
                    context.translateBy(x: -size / 2, y: -size / 2)
                    context.draw(sharp, in: rect)
                    context.restoreGState()
                }
            }
            images = smear.map { Images(sharp: sharp, smear: $0, shadow: shadow) }
        }
        return images
    }

    /// Finish colors, approximated from Apple's product photos.
    static func tint(for color: SpinnerColor) -> NSColor {
        let hex: UInt32 = switch color {
        case .cosmicOrange: 0xF0722C
        case .deepBlue: 0x2F3E5C
        case .silver: 0xDCDDDF
        case .spaceBlack: 0x2A2A2D
        case .skyBlue: 0xB9D4EC
        case .lightGold: 0xE6D5B0
        case .lavender: 0xC8B8E4
        case .mistBlue: 0xA3B9D3
        case .sage: 0xA6B596
        case .pink: 0xF1B5C4
        case .ultramarine: 0x5767DB
        case .teal: 0x78C2BE
        }
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func draw(size: CGFloat, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage? {
        let pixels = Int(size * scale)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        body(context)
        return context.makeImage()
    }

    private struct Geometry {
        let center: CGPoint
        let lobes: [CGPoint]
        let lobeRadius: CGFloat
        let hubRadius: CGFloat
        /// Body outline: one true union, so the hairline follows only the outer edge.
        let body: CGPath

        init(size: CGFloat) {
            center = CGPoint(x: size / 2, y: size / 2)
            // Leave a margin for the shadow's blur.
            let unit = size * 0.43
            let lobeDistance = unit * 0.62
            lobeRadius = unit * 0.37
            hubRadius = unit * 0.44
            let armWidth = lobeRadius * 1.35
            let center = center
            lobes = (0..<3).map { index -> CGPoint in
                let angle = CGFloat(index) * 2 * .pi / 3 + .pi / 2
                return CGPoint(x: center.x + cos(angle) * lobeDistance, y: center.y + sin(angle) * lobeDistance)
            }
            var body = CGPath(ellipseIn: SpinnerArtwork.circle(center, hubRadius), transform: nil)
            for lobe in lobes {
                body = body
                    .union(CGPath(ellipseIn: SpinnerArtwork.circle(lobe, lobeRadius), transform: nil))
                    .union(SpinnerArtwork.arm(from: center, to: lobe, width: armWidth))
            }
            self.body = body
        }
    }

    /// Only the blur: the silhouette is drawn far off canvas and its shadow
    /// cast back onto it, with no offset (the view offsets the layer).
    /// Shadow offset and blur are in device pixels, so they take the scale.
    private static func drawShadow(in context: CGContext, size: CGFloat, scale: CGFloat, isDark: Bool) {
        let geometry = Geometry(size: size)
        let away = size * 4
        context.setShadow(offset: CGSize(width: away * scale, height: 0), blur: size * 0.07 * scale,
                          color: CGColor(gray: 0, alpha: isDark ? 0.55 : 0.3))
        context.translateBy(x: -away, y: 0)
        context.addPath(geometry.body)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
    }

    private static func drawSpinner(in context: CGContext, size: CGFloat, tint: NSColor, isDark: Bool) {
        let geometry = Geometry(size: size)
        let body = geometry.body
        let lobes = geometry.lobes, lobeRadius = geometry.lobeRadius
        let hubRadius = geometry.hubRadius, center = geometry.center

        let finish = tint.usingColorSpace(.sRGB) ?? tint
        let isLight = finish.brightnessComponent > 0.75 && finish.saturationComponent < 0.35

        context.addPath(body)
        context.setFillColor(finish.cgColor)
        context.fillPath()

        // Hairline: dark on light finishes, light on dark ones and in dark mode.
        context.addPath(body)
        context.setStrokeColor(shade(finish, by: isLight ? -0.18 : (isDark ? 0.25 : -0.22)).cgColor)
        context.setLineWidth(max(0.5, size * 0.006))
        context.strokePath()

        for lobe in lobes {
            drawBearing(in: context, at: lobe, radius: lobeRadius * 0.6, finish: finish)
        }
        drawCap(in: context, at: center, radius: hubRadius * 0.52, finish: finish)
    }

    /// A bearing: a recessed ring in a darker tone of the finish, with a darker core.
    private static func drawBearing(in context: CGContext, at point: CGPoint, radius: CGFloat, finish: NSColor) {
        context.setFillColor(shade(finish, by: -0.12).cgColor)
        context.fillEllipse(in: circle(point, radius))
        context.setStrokeColor(shade(finish, by: -0.28).cgColor)
        context.setLineWidth(max(0.5, radius * 0.08))
        context.strokeEllipse(in: circle(point, radius * 0.96))
        context.setFillColor(shade(finish, by: -0.4).cgColor)
        context.fillEllipse(in: circle(point, radius * 0.42))
    }

    /// The center cap: a slightly raised disc of the same finish, set off by a ring.
    private static func drawCap(in context: CGContext, at point: CGPoint, radius: CGFloat, finish: NSColor) {
        let cap = circle(point, radius)
        context.saveGState()
        // No offset: a directional shadow here would also circle as it turns.
        context.setShadow(offset: .zero, blur: radius * 0.25, color: CGColor(gray: 0, alpha: 0.25))
        context.setFillColor(shade(finish, by: 0.06).cgColor)
        context.fillEllipse(in: cap)
        context.restoreGState()
        context.setStrokeColor(shade(finish, by: -0.25).cgColor)
        context.setLineWidth(max(0.5, radius * 0.06))
        context.strokeEllipse(in: cap.insetBy(dx: radius * 0.03, dy: radius * 0.03))
    }

    /// Lighter (positive) or darker (negative) version of a color.
    private static func shade(_ color: NSColor, by amount: CGFloat) -> NSColor {
        let target: NSColor = amount >= 0 ? .white : .black
        return color.blended(withFraction: abs(amount), of: target) ?? color
    }

    nonisolated fileprivate static func arm(from start: CGPoint, to end: CGPoint, width: CGFloat) -> CGPath {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        var transform = CGAffineTransform(translationX: start.x, y: start.y).rotated(by: angle)
        return CGPath(rect: CGRect(x: 0, y: -width / 2, width: length, height: width), transform: &transform)
    }

    nonisolated fileprivate static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
