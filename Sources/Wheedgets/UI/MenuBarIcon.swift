import AppKit

/// The app icon's bubble, reduced to a monochrome template for the menu bar:
/// an outline and one highlight arc. Drawn as vectors, so it's sharp
/// at any scale; as a template, macOS tints it for light, dark and pressed.
@MainActor
enum MenuBarIcon {
    /// Everything off.
    static let bubble = make(filled: false)
    /// A widget is on: the same bubble, filled in.
    static let filledBubble = make(filled: true)

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(filled: filled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Wheedgets"
        return image
    }

    /// Design space: 18 × 18 pt, origin bottom left.
    private static func draw(filled: Bool) {
        let center = NSPoint(x: 9, y: 9)
        let radius: CGFloat = 6.8

        let outline = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        if filled {
            NSColor.black.withAlphaComponent(0.35).setFill()
            outline.fill()
        }
        outline.lineWidth = 1.5
        NSColor.black.setStroke()
        outline.stroke()

        // Highlight arc, upper left inside the bubble.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius * 0.58, startAngle: 112, endAngle: 158)
        arc.lineWidth = 1.5
        arc.lineCapStyle = .round
        arc.stroke()
    }
}
