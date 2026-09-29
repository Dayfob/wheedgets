import AppKit
import Observation
import OSLog
import WheedgetsCore

/// Mechanical keyboard sounds while you type.
///
/// Always pass-through: it gets a listen-only tap, so typing is never delayed.
/// It only looks at which physical key moved to pick a sound; nothing typed is
/// kept or logged.
@MainActor
@Observable
final class KeyboardSounds: Widget {
    enum PackStatus: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let kind = WidgetKind.keyboardSounds
    let keyHandling = KeyHandling.passThrough

    var settings: KeyboardSoundSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private(set) var packStatus: PackStatus = .idle
    private(set) var installedPacks: [InstalledKeyPack] = []

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let audio: AudioEngine
    @ObservationIgnored private let channel: AudioChannel
    @ObservationIgnored private let library: KeyPackLibrary
    @ObservationIgnored private var loaded: LoadedKeyPack?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var isOn = false

    init(settings: KeyboardSoundSettings, audio: AudioEngine, library: KeyPackLibrary) {
        self.settings = settings
        self.audio = audio
        self.library = library
        channel = audio.makeChannel(voices: 24)
        channel.volume = settings.volume
        installedPacks = library.installedPacks()
        audio.addFormatObserver { [weak self] _ in
            guard let self, self.loaded != nil else { return }
            self.reloadPack()
        }
    }

    // MARK: - Widget

    var volume: Float {
        get { settings.volume }
        set { settings.volume = newValue }
    }

    func isBound(_ keyCode: UInt16) -> Bool { false }

    func handleKey(_ event: KeyEvent) {
        guard !event.isRepeat, let loaded,
              let code = MechvibesKeyCodes.code(for: event.keyCode) else { return }
        let phase: KeySoundPack.Phase = event.isDown ? .press : .release
        if phase == .release && !settings.playsReleaseSounds { return }
        guard let buffer = loaded.buffer(for: code, phase: phase) else { return }
        // Real keystrokes are never equally loud.
        channel.play(buffer, gain: Float.random(in: 0.8...1))
    }

    func widgetDidTurnOn() {
        isOn = true
        if loaded?.id != settings.pack { reloadPack() }
    }

    func widgetDidTurnOff() {
        isOn = false
    }

    /// Plays a key press, for previewing a pack from Settings.
    func preview() {
        if loaded?.id != settings.pack { reloadPack() }
        guard let buffer = loaded?.buffer(for: MechvibesKeyCodes.generic, phase: .press) else { return }
        channel.play(buffer)
    }

    // MARK: - Packs

    private func reloadPack() {
        loadTask?.cancel()
        let id = settings.pack
        let folder: URL? = if case .imported(let name) = id { library.folderURL(name) } else { nil }
        let sampleRate = audio.format.sampleRate
        loaded = nil
        packStatus = .loading

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try KeyPackLoader.load(id, folder: folder, sampleRate: sampleRate)
            }.result
            guard let self, !Task.isCancelled, self.settings.pack == id else { return }
            switch result {
            case .success(let pack):
                self.loaded = pack
                self.packStatus = .ready
            case .failure(let error):
                Logger.audio.error("Keyboard pack failed to load: \(error.localizedDescription)")
                self.packStatus = .failed(error.localizedDescription)
            }
        }
    }

    func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a Mechvibes sound pack folder or .zip file")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try library.importPack(from: url)
            installedPacks = library.installedPacks()
            settings.pack = pack.id
        } catch {
            Alerts.show(title: String(localized: "Couldn't Import This Pack"), message: error.localizedDescription)
        }
    }

    func removePack(_ pack: InstalledKeyPack) {
        if settings.pack == pack.id { settings.pack = .default }
        library.remove(pack.folder)
        installedPacks = library.installedPacks()
    }

    func revealPacksInFinder() {
        try? FileManager.default.createDirectory(at: library.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(library.directory)
    }

    // MARK: - Settings

    private func settingsDidChange(from old: KeyboardSoundSettings) {
        if settings.volume != old.volume {
            channel.volume = settings.volume
        }
        if settings.pack != old.pack, isOn || loaded != nil {
            reloadPack()
        }
        onChange()
    }
}
