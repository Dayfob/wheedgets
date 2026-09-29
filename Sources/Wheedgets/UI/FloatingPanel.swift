import AppKit
import SwiftUI

/// A floating HUD that never takes keyboard focus: clicking it leaves the
/// frontmost app active, so typing keeps going where it was.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel never becomes key, so every click is a "first mouse" click.
/// Accepting it makes buttons and sliders respond on the first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows SwiftUI content in a `FloatingPanel` that sizes itself to the
/// content and remembers where the user dragged it.
@MainActor
final class FloatingPanelController<Content: View> {
    private let panel = FloatingPanel()
    private let hostingView: FirstMouseHostingView<Content>

    init(rootView: Content, autosaveName: String) {
        hostingView = FirstMouseHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        if !panel.setFrameUsingName(autosaveName) {
            placeInDefaultPosition()
        }
        panel.setFrameAutosaveName(autosaveName)
    }

    func setVisible(_ visible: Bool) {
        fitToContent()
        if visible, !panel.isVisible {
            panel.orderFrontRegardless()
        } else if !visible, panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Resizes for the current content, keeping the top edge in place.
    func fitToContent() {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        var frame = panel.frame
        guard frame.size != size else { return }
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func placeInDefaultPosition() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
    }
}

/// Behind-window blur with rounded corners that also drags the panel.
struct PanelBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    final class DraggableEffectView: NSVisualEffectView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DraggableEffectView {
        let view = DraggableEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: DraggableEffectView, context: Context) {}

    /// A stretchable mask is the reliable way to round a behind-window blur.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A small borderless icon button for panel headers.
struct PanelIconButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
