import SwiftUI
import WheedgetsCore

/// Shows the pad panel while the drums are on, unless the user hid it.
@MainActor
final class DrumPanelController {
    private let panel: FloatingPanelController<DrumPanelView>

    init(drums: DrumKit, host: WidgetHost, openSettings: @escaping @MainActor () -> Void) {
        panel = FloatingPanelController(
            rootView: DrumPanelView(drums: drums, host: host, openSettings: openSettings),
            autosaveName: "DrumPanel"
        )
        observeChanges { [weak self] in
            // Reading these re-fits the panel when its layout changes.
            _ = drums.settings.pads.count
            _ = drums.settings.control
            _ = drums.settings.trackpad.rows
            _ = drums.settings.trackpad.layout
            self?.panel.setVisible(drums.isOn && drums.settings.showsPanel)
        }
    }
}
