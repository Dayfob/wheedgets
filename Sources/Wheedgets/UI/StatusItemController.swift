import AppKit
import WheedgetsCore

/// The menu bar icon and its menu. The menu shows the widget list, then only
/// what concerns the selected widget.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let host: WidgetHost
    private let drums: DrumKit
    private let keyboardSounds: KeyboardSounds
    private let openSettingsAction: @MainActor () -> Void

    init(host: WidgetHost, drums: DrumKit, keyboardSounds: KeyboardSounds, openSettings: @escaping @MainActor () -> Void) {
        self.host = host
        self.drums = drums
        self.keyboardSounds = keyboardSounds
        openSettingsAction = openSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        observeChanges { [weak self] in
            guard let self else { return }
            self.updateIcon(state: self.host.state, selected: self.host.settings.selected)
        }
    }

    /// Always the app's bubble, whichever widget is active: outlined when
    /// everything is off, filled in while a widget runs.
    private func updateIcon(state: WidgetHost.State, selected: WidgetKind) {
        guard let button = statusItem.button else { return }
        let description = switch state {
        case .on: String(localized: "Wheedgets: \(selected.displayName) is on")
        case .off: String(localized: "Wheedgets")
        case .waitingForPermission: String(localized: "Wheedgets: waiting for Accessibility access")
        }
        button.image = state == .on ? MenuBarIcon.filledBubble : MenuBarIcon.bubble
        button.setAccessibilityLabel(description)
        button.toolTip = description
    }

    // MARK: - Menu

    /// Rebuilt on every open, so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let selected = host.settings.selected
        let isOn = host.state == .on

        for kind in WidgetKind.allCases {
            let entry = item(kind.displayName, #selector(switchWidget(_:)))
            entry.representedObject = kind.rawValue
            entry.image = NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil)
            entry.state = kind == selected ? .on : .off
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let toggleTitle = isOn
            ? String(localized: "Turn Off \(selected.displayName)")
            : String(localized: "Turn On \(selected.displayName)")
        let toggle = item(toggleTitle, #selector(toggleWidget))
        let hotkey = host.settings.hotkey
        let keyName = KeyNames.name(for: hotkey.keyCode)
        if keyName.count == 1 {
            toggle.keyEquivalent = keyName.lowercased()
            toggle.keyEquivalentModifierMask = hotkey.modifiers.eventFlags
        }
        menu.addItem(toggle)
        host.accessibility.refresh()
        if !host.accessibility.isTrusted {
            menu.addItem(item(String(localized: "Grant Accessibility Access…"), #selector(grantAccess)))
        }

        menu.addItem(.separator())
        let volume = NSMenuItem()
        volume.view = VolumeMenuView(
            title: String(localized: "Volume"),
            value: host.selected.volume,
            range: Volume.module
        ) { [weak self] in self?.host.selected.volume = $0 }
        menu.addItem(volume)
        addExtras(for: selected, to: menu)

        menu.addItem(.separator())
        let settings = item(String(localized: "Settings…"), #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(withTitle: String(localized: "Quit Wheedgets"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// The one or two things worth reaching from the menu for each widget.
    private func addExtras(for kind: WidgetKind, to menu: NSMenu) {
        switch kind {
        case .drums:
            let pads = item(String(localized: "Show Pads"), #selector(toggleDrumPads))
            pads.state = drums.settings.showsPanel ? .on : .off
            menu.addItem(pads)
        case .keyboardSounds:
            let packs = NSMenu()
            let choices: [(KeyPackID, String)] = [
                (.builtin(.clicky), String(localized: "Clicky")),
                (.builtin(.thocky), String(localized: "Thocky"))
            ] + keyboardSounds.installedPacks.map { ($0.id, $0.name) }
            for (id, name) in choices {
                let entry = item(name, #selector(selectPack(_:)))
                entry.representedObject = id.rawValue
                entry.state = keyboardSounds.settings.pack == id ? .on : .off
                packs.addItem(entry)
            }
            let packItem = NSMenuItem(title: String(localized: "Sound Pack"), action: nil, keyEquivalent: "")
            packItem.submenu = packs
            menu.addItem(packItem)
        case .spinner:
            break
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func switchWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = WidgetKind(rawValue: raw) else { return }
        host.switchTo(kind)
    }

    @objc private func toggleWidget() { host.toggle() }
    @objc private func grantAccess() { host.accessibility.request() }
    @objc private func toggleDrumPads() { drums.settings.showsPanel.toggle() }
    @objc private func openSettings() { openSettingsAction() }

    @objc private func selectPack(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = KeyPackID(rawValue: raw) else { return }
        keyboardSounds.settings.pack = id
    }
}

/// A native slider row for the menu: SwiftUI inside a tracking menu can lag,
/// NSSlider cannot.
private final class VolumeMenuView: NSView {
    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let range: ClosedRange<Float>
    private let onChange: (Float) -> Void

    init(title: String, value: Float, range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) {
        self.range = range
        self.onChange = onChange
        slider = NSSlider(
            value: Double(value),
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 30))

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.controlSize = .small

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let stack = NSStackView(views: [titleLabel, slider, valueLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func sliderChanged() {
        let snapped = VolumeSlider.snapped(slider.floatValue, in: range)
        slider.floatValue = snapped
        updateLabel()
        onChange(snapped)
    }

    private func updateLabel() {
        valueLabel.stringValue = "\(Int((slider.floatValue * 100).rounded()))%"
    }
}
