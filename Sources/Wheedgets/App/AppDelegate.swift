import AppKit
import WheedgetsCore

/// Composition root: builds the shared services, the modules and the UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let watchdog = MainThreadWatchdog()
    private var host: WidgetHost?
    private var statusItem: StatusItemController?
    private var drumPanel: DrumPanelController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchdog.start()
        let settings = store.load()

        // Shared services
        let audio = AudioEngine(masterVolume: settings.masterVolume)
        let keyboard = KeyboardHub()
        let accessibility = AccessibilityStatus()

        // Widgets
        let drums = DrumKit(settings: settings.drums, audio: audio, samples: SampleLibrary())
        let spinner = Spinner(settings: settings.spinner, audio: audio)
        let keyboardSounds = KeyboardSounds(settings: settings.keyboardSounds, audio: audio, library: KeyPackLibrary())
        let host = WidgetHost(
            settings: settings.widgets,
            widgets: [drums, spinner, keyboardSounds],
            keyboard: keyboard,
            accessibility: accessibility
        )
        drums.onKeyHandlingChange = { host.keyHandlingDidChange() }
        spinner.onKeyHandlingChange = { host.keyHandlingDidChange() }

        // Persistence: every part reports changes, the store gathers them.
        store.snapshot = {
            AppSettings(
                masterVolume: audio.masterVolume,
                widgets: host.settings,
                drums: drums.settings,
                spinner: spinner.settings,
                keyboardSounds: keyboardSounds.settings
            )
        }
        let save: () -> Void = { [store] in store.scheduleSave() }
        audio.onChange = save
        host.onChange = save
        drums.onChange = save
        spinner.onChange = save
        keyboardSounds.onChange = save

        // UI
        let settingsWindow = SettingsWindowController(
            content: {
                SettingsView(host: host, audio: audio, drums: drums, spinner: spinner, keyboardSounds: keyboardSounds)
            },
            // A recorder left listening would keep the shortcut unregistered.
            onClose: { host.activeRecorder = nil }
        )
        let openSettings: @MainActor () -> Void = { settingsWindow.show() }

        self.host = host
        self.settingsWindow = settingsWindow
        statusItem = StatusItemController(host: host, drums: drums, keyboardSounds: keyboardSounds, openSettings: openSettings)
        drumPanel = DrumPanelController(drums: drums, host: host, openSettings: openSettings)
        NSApp.mainMenu = MainMenu.make(openSettings: #selector(showSettings))
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.turnOff()
        store.saveNow()
    }

    /// Launching the app again from Finder or Spotlight opens Settings, since
    /// there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }

    @objc func showSettings() {
        settingsWindow?.show()
    }
}

/// An accessory app shows no menu bar, but key equivalents like ⌘W and ⌘Q
/// still come from the main menu while the Settings window is focused.
@MainActor
enum MainMenu {
    static func make(openSettings: Selector) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: openSettings, keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Wheedgets"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }
}
