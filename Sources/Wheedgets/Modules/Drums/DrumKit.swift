import AppKit
import AVFoundation
import Observation
import WheedgetsCore

/// The drums widget: pads bound to keys, or zones on the trackpad, each
/// playing a synthesized drum or an imported sample.
@MainActor
@Observable
final class DrumKit: Widget {
    let kind = WidgetKind.drums

    var settings: DrumSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    /// Bumped on every hit; pads animate when their token changes.
    private(set) var hitTokens: [Pad.ID: Int] = [:]
    /// Same for trackpad zones, by zone index.
    private(set) var zoneHitTokens: [Int: Int] = [:]
    /// Same for custom zones, by id.
    private(set) var customZoneHitTokens: [CustomZone.ID: Int] = [:]

    /// Drawing a zone by tracing it on the trackpad.
    enum Tracing: Equatable {
        case idle
        /// The finger's path so far (empty until it touches down).
        case drawing([ZonePoint])
        /// The last trace was too small or too thin to be a zone.
        case rejected
    }

    private(set) var tracing: Tracing = .idle
    /// The custom zone being edited in Settings.
    var selectedCustomZone: CustomZone.ID?
    /// The pad panel is shown while the drums are on.
    private(set) var isOn = false

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored var onKeyHandlingChange: () -> Void = {}
    @ObservationIgnored private let audio: AudioEngine
    @ObservationIgnored private let channel: AudioChannel
    @ObservationIgnored private let samples: SampleLibrary
    @ObservationIgnored private var padsByKey: [UInt16: Pad]
    @ObservationIgnored private var clickMonitors: [Any] = []
    @ObservationIgnored private var tracingTimer: Timer?
    private static let tracingOwner = "zoneTracing"
    /// Strength for clicks, which are placed on the main thread.
    @ObservationIgnored private var clickStrength = TrackpadHitDetector()
    private static let trackpadOwner = "drums"

    init(settings: DrumSettings, audio: AudioEngine, samples: SampleLibrary) {
        self.settings = settings
        self.audio = audio
        self.samples = samples
        channel = audio.makeChannel(voices: 16)
        channel.volume = settings.volume
        padsByKey = settings.padsByKey
        preload()
        audio.addFormatObserver { [weak self] _ in self?.preload() }
    }

    // MARK: - Widget

    var keyHandling: KeyHandling { settings.keyHandling }

    var usesKeyboard: Bool { settings.control == .keyboard }

    var volume: Float {
        get { settings.volume }
        set { settings.volume = newValue }
    }

    func isBound(_ keyCode: UInt16) -> Bool {
        padsByKey[keyCode] != nil
    }

    func handleKey(_ event: KeyEvent) {
        // In pass-through mode every key arrives here; shortcuts don't drum.
        guard event.isDown, !event.isRepeat, !event.isModifier, !event.hasShortcutModifier,
              let pad = padsByKey[event.keyCode] else { return }
        trigger(pad)
    }

    func widgetDidTurnOn() {
        isOn = true
        updateTrackpad()
    }

    func widgetDidTurnOff() {
        isOn = false
        updateTrackpad()
    }

    // MARK: - Trackpad

    var trackpadAvailable: Bool { MultitouchTrackpad.isAvailable }

    /// Reads the trackpad only while the drums are on and set to it. Nothing
    /// is blocked: clicks and the pointer keep working as usual.
    private func updateTrackpad() {
        removeClickMonitors()
        guard isOn && settings.control == .trackpad else {
            MultitouchTrackpad.stop(owner: Self.trackpadOwner)
            return
        }
        let taps = settings.trackpad.trigger == .tap
        MultitouchTrackpad.onHits = { [weak self] hits in
            for hit in hits { self?.play(hit) }
        }
        MultitouchTrackpad.start(.drums(reportsTaps: taps), owner: Self.trackpadOwner)
        if !taps { addClickMonitors() }
    }

    /// Clicks are observed, never consumed. The finger pressing hardest
    /// (the largest contact) is the one that clicked.
    private func addClickMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick() }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) {
            clickMonitors.append(local)
        }
    }

    private func removeClickMonitors() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    private func handleClick() {
        // A mouse click has no finger on the trackpad; it stays silent.
        guard let finger = MultitouchTrackpad.touchingContacts().max(by: { $0.size < $1.size }) else { return }
        play(.init(x: finger.x, y: finger.y, strength: clickStrength.strength(for: finger.size)))
    }

    private func play(_ hit: TrackpadHitDetector.Hit) {
        let grid = settings.trackpad
        let strength = grid.velocitySensitive ? hit.strength : 1
        switch grid.layout {
        case .grid:
            playZone(grid.zoneIndex(x: hit.x, y: hit.y), strength: strength)
        case .custom:
            // Outside every zone the trackpad stays silent.
            guard let index = grid.customZoneIndex(at: ZonePoint(x: hit.x, y: hit.y)) else { return }
            playCustomZone(grid.customZones[index].id, strength: strength)
        }
    }

    func playCustomZone(_ id: CustomZone.ID, strength: Double = 1) {
        guard let zone = settings.trackpad.customZones.first(where: { $0.id == id }),
              let buffer = buffer(for: zone.sound) else { return }
        channel.play(buffer, gain: Float(strength), pan: zone.sound.pan)
        customZoneHitTokens[id, default: 0] &+= 1
    }

    // MARK: - Custom zones

    /// Records the next finger path on the trackpad as a new zone.
    func startTracing() {
        guard MultitouchTrackpad.start(.tracing, owner: Self.tracingOwner) else { return }
        tracing = .drawing([])
        tracingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTracing() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracingTimer = timer
    }

    func cancelTracing() {
        endTracing()
        tracing = .idle
    }

    private func pollTracing() {
        let (points, finished) = MultitouchTrackpad.tracedPath()
        guard finished else {
            tracing = .drawing(points)
            return
        }
        endTracing()
        guard let outline = ZoneTracing.outline(from: points) else {
            tracing = .rejected
            return
        }
        let zone = CustomZone(outline: outline, sound: nextZoneSound())
        settings.trackpad.customZones.append(zone)
        settings.trackpad.layout = .custom
        selectedCustomZone = zone.id
        tracing = .idle
        playCustomZone(zone.id)
    }

    private func endTracing() {
        tracingTimer?.invalidate()
        tracingTimer = nil
        MultitouchTrackpad.stop(owner: Self.tracingOwner)
    }

    /// New zones cycle through the kit, so each one sounds different at first.
    private func nextZoneSound() -> SoundSource {
        let order: [DrumSound] = [.kick, .snare, .closedHat, .openHat, .crash, .tomHigh, .tomLow, .ride, .clap, .rim, .tomMid, .cowbell]
        return .builtin(order[settings.trackpad.customZones.count % order.count])
    }

    func setCustomZoneSound(_ id: CustomZone.ID, to source: SoundSource) {
        guard let index = settings.trackpad.customZones.firstIndex(where: { $0.id == id }) else { return }
        settings.trackpad.customZones[index].sound = source
        playCustomZone(id)
    }

    func chooseSample(forCustomZone id: CustomZone.ID) {
        if let source = pickSample() { setCustomZoneSound(id, to: source) }
    }

    func removeCustomZone(_ id: CustomZone.ID) {
        settings.trackpad.customZones.removeAll { $0.id == id }
        if selectedCustomZone == id { selectedCustomZone = nil }
    }

    func removeAllCustomZones() {
        settings.trackpad.customZones.removeAll()
        selectedCustomZone = nil
    }

    /// Plays a zone; also used by clicks on the panel.
    func playZone(_ zone: Int, strength: Double = 1) {
        let zones = settings.trackpad.zones
        guard zones.indices.contains(zone), let buffer = buffer(for: zones[zone]) else { return }
        channel.play(buffer, gain: Float(strength), pan: zones[zone].pan)
        zoneHitTokens[zone, default: 0] &+= 1
    }

    // MARK: - Playing

    func trigger(_ pad: Pad) {
        guard let buffer = buffer(for: pad.source) else { return }
        channel.play(buffer, gain: pad.gain, pan: pad.source.pan)
        hitTokens[pad.id, default: 0] &+= 1
    }

    private func buffer(for source: SoundSource) -> AVAudioPCMBuffer? {
        audio.buffer(for: source) { format in
            switch source {
            case .builtin(let sound):
                SampleDecoder.buffer(mono: DrumSynth.render(sound, sampleRate: format.sampleRate), format: format)
            case .sample(let fileName, _):
                SampleDecoder.load(samples.url(for: fileName), as: format)
            }
        }
    }

    /// Renders and loads ahead of time, so a key press never waits on I/O.
    private func preload() {
        let trackpad = settings.trackpad
        for source in settings.pads.map(\.source) + trackpad.zones + trackpad.customZones.map(\.sound) {
            _ = buffer(for: source)
        }
    }

    // MARK: - Editing

    func updatePad(_ id: Pad.ID, _ change: (inout Pad) -> Void) {
        guard let index = settings.pads.firstIndex(where: { $0.id == id }) else { return }
        change(&settings.pads[index])
    }

    func setSound(_ source: SoundSource, forPad id: Pad.ID) {
        updatePad(id) { $0.source = source }
        if let pad = settings.pads.first(where: { $0.id == id }) { trigger(pad) }
    }

    func removePad(_ id: Pad.ID) {
        settings.pads.removeAll { $0.id == id }
    }

    func addPad() {
        if settings.addPad() == nil { NSSound.beep() }
    }

    func restoreDefaultKit() {
        settings.pads = Pad.makeDefaultKit()
    }

    func chooseSample(forPad id: Pad.ID) {
        if let source = pickSample() { setSound(source, forPad: id) }
    }

    func setZone(row: Int, column: Int, to source: SoundSource) {
        settings.trackpad.setZone(row: row, column: column, to: source)
        playZone(row * settings.trackpad.columns + column)
    }

    func chooseSample(forZoneRow row: Int, column: Int) {
        if let source = pickSample() { setZone(row: row, column: column, to: source) }
    }

    func resizeTrackpadGrid(rows: Int, columns: Int) {
        settings.trackpad.resize(rows: rows, columns: columns)
        zoneHitTokens.removeAll()
    }

    /// Asks for an audio file and copies it into the sample library.
    private func pickSample() -> SoundSource? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a sound for this pad")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try samples.importSample(from: url)
        } catch {
            Alerts.show(title: String(localized: "Couldn't Use This File"), message: error.localizedDescription)
            return nil
        }
    }

    private func settingsDidChange(from old: DrumSettings) {
        if settings.pads != old.pads || settings.trackpad.zones != old.trackpad.zones
            || settings.trackpad.customZones != old.trackpad.customZones {
            padsByKey = settings.padsByKey
            preload()
            samples.removeUnused(keeping: settings.referencedSampleFiles)
        }
        if settings.control != old.control || settings.trackpad.trigger != old.trackpad.trigger {
            updateTrackpad()
        }
        if settings.volume != old.volume {
            channel.volume = settings.volume
        }
        if settings.keyHandling != old.keyHandling || settings.control != old.control {
            onKeyHandlingChange()
        }
        onChange()
    }
}

extension SoundSource {
    var pan: Float {
        if case .builtin(let sound) = self { sound.pan } else { 0 }
    }
}
