import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeContent: () -> SettingsView
    private let onClose: () -> Void
    private var window: NSWindow?

    init(content: @escaping () -> SettingsView, onClose: @escaping () -> Void) {
        makeContent = content
        self.onClose = onClose
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: makeContent())
        controller.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Wheedgets Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 820, height: 680))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
