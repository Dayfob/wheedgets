import AppKit
import QuartzCore
import WheedgetsCore

/// Draws the spinner at an angle, with a motion trail and blur that grow
/// with speed. Pure Core Animation: rotating layers is almost free.
final class SpinnerView: NSView {
    private let shadowLayer = CALayer()
    private let smearLayer = CALayer()
    private let trailLayers = (0..<3).map { _ in CALayer() }
    private let bodyLayer = CALayer()

    /// Called every display frame while the link runs, with the frame's duration.
    var onFrame: ((Double) -> Void)?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        for sublayer in [shadowLayer, smearLayer] + trailLayers.reversed() + [bodyLayer] {
            sublayer.contentsGravity = .resizeAspect
            layer?.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// True while the user drags the spinner around the screen.
    private(set) var isDragging = false
    private var grabOffset = CGPoint.zero

    // Dragged by hand rather than with performDrag, so `isDragging` is exact.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        grabOffset = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setArtwork(_ images: SpinnerArtwork.Images, size: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        smearLayer.contents = images.smear
        shadowLayer.contents = images.shadow
        for layer in trailLayers + [bodyLayer] { layer.contents = images.sharp }
        for layer in [shadowLayer, smearLayer, bodyLayer] + trailLayers {
            layer.bounds = bounds
            layer.position = center
            layer.contentsScale = window?.backingScaleFactor ?? 2
        }
        // The light comes from above: the shadow always falls downward.
        shadowLayer.position = CGPoint(x: center.x, y: center.y - size * SpinnerArtwork.shadowDrop)
        CATransaction.commit()
    }

    /// - Parameters:
    ///   - angle: in turns, 0…1, clockwise.
    ///   - step: how far it turns per frame, in turns (drives blur and trail).
    func show(angle: Double, step: Double) {
        let radians = -angle * 2 * .pi
        let stepRadians = -step * 2 * .pi
        let travel = abs(step)
        // A tri-lobe looks identical every 1/3 turn; past ~1/12 turn per frame
        // the eye sees a blurred disc rather than arms.
        let smear = Float(((travel - 0.03) / 0.08).clamped(to: 0...1))
        let trail = Float((travel / 0.02).clamped(to: 0...1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyLayer.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
        shadowLayer.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
        bodyLayer.opacity = 1 - smear * 0.85
        for (index, layer) in trailLayers.enumerated() {
            let lag = Double(index + 1) / 3
            layer.transform = CATransform3DMakeRotation(radians - stepRadians * lag, 0, 0, 1)
            layer.opacity = trail * [0.35, 0.2, 0.1][index] * (1 - smear)
        }
        smearLayer.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
        smearLayer.opacity = smear
        CATransaction.commit()
    }

    var isAnimating: Bool {
        link.map { !$0.isPaused } ?? false
    }

    func setAnimating(_ animating: Bool) {
        if animating {
            if link == nil {
                let link = displayLink(target: self, selector: #selector(frame(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            }
            lastTimestamp = nil
            link?.isPaused = false
        } else {
            link?.isPaused = true
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let dt = lastTimestamp.map { link.timestamp - $0 } ?? link.duration
        lastTimestamp = link.timestamp
        onFrame?(dt)
    }
}

/// A transparent window that floats above everything, even full-screen apps.
///
/// It takes the mouse only while the pointer is over the spinner itself, so
/// the spinner can be dragged directly while clicks anywhere else, including
/// the empty corners of its square window, go to whatever is underneath.
@MainActor
final class SpinnerOverlay {
    let view: SpinnerView
    private let panel: FloatingPanel
    private var hoverTimer: Timer?
    private var size: CGFloat = 0

    /// Called when the look must be redrawn: light/dark or accent color changed.
    var onAppearanceChange: () -> Void = {}
    private var appearanceObservation: NSKeyValueObservation?
    private var accentObserver: Any?

    init() {
        panel = FloatingPanel()
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        view = SpinnerView(frame: .zero)
        panel.contentView = view

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onAppearanceChange() } }
        }
        accentObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onAppearanceChange() }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var isDragging: Bool { view.isDragging }

    /// Polls the pointer while visible: cheaper and more reliable than global
    /// mouse-moved monitors, and needs no permission.
    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseCapture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        panel.ignoresMouseEvents = true
    }

    private func updateMouseCapture() {
        guard !view.isDragging else { return }
        // Don't grab a drag that started elsewhere (e.g. a file being carried).
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        // The body reaches about 0.44 of the window size from the center.
        let overSpinner = hypot(mouse.x - frame.midX, mouse.y - frame.midY) <= size * 0.44
        if panel.ignoresMouseEvents == overSpinner {
            panel.ignoresMouseEvents = !overSpinner
        }
    }

    func configure(size: CGFloat, color: SpinnerColor) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let images = SpinnerArtwork.render(color: color, size: size, scale: scale, appearance: NSApp.effectiveAppearance) else { return }
        if size != self.size {
            // Keep the spinner centered where it was.
            let old = panel.frame
            let frame = NSRect(x: old.midX - size / 2, y: old.midY - size / 2, width: size, height: size)
            let firstPlacement = self.size == 0
            self.size = size
            panel.setContentSize(frame.size)
            if firstPlacement {
                if !panel.setFrameUsingName("SpinnerOverlay") { placeInDefaultPosition() }
                panel.setContentSize(frame.size)
                panel.setFrameAutosaveName("SpinnerOverlay")
            } else {
                panel.setFrame(frame, display: true)
            }
            view.frame = NSRect(origin: .zero, size: frame.size)
        }
        view.setArtwork(images, size: size)
    }

    func setVisible(_ visible: Bool) {
        visible ? startHoverTracking() : stopHoverTracking()
        if visible, !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        } else if !visible, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            } completionHandler: { [panel] in
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            }
        }
    }

    func resetPosition() {
        placeInDefaultPosition()
    }

    private func placeInDefaultPosition() {
        // Bottom-right corner, clear of the Dock and the screen edge.
        guard let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 40, y: screen.minY + 40))
    }
}
