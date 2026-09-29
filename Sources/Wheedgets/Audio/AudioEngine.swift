import AVFoundation
import Observation
import OSLog
import WheedgetsCore

/// The one audio engine every module plays through.
///
/// macOS mixes every app's audio together, so the only way to disturb other
/// audio is to ask for it. This engine deliberately never:
/// - touches `inputNode` — merely accessing it can switch Bluetooth headphones
///   into low-quality headset mode, which degrades *all* system audio;
/// - enables voice processing, which ducks other apps' audio;
/// - changes the output device, its sample rate, or the system volume.
///
/// Graph: module channels → master bus → master limiter → main mixer (master volume) → output.
@MainActor
@Observable
final class AudioEngine {
    /// Silence this long stops the engine, even with a widget on: restarting
    /// takes a few milliseconds, while running costs CPU all the time.
    private static let idleShutdown: Duration = .seconds(30)

    /// 0…1, applied after every module.
    var masterVolume: Float {
        didSet {
            engine.mainMixerNode.outputVolume = masterVolume.clamped(to: Volume.master)
            onChange()
        }
    }

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private(set) var format: AVAudioFormat
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let masterBus = AVAudioMixerNode()
    @ObservationIgnored private let masterLimiter = AVAudioUnitEffect.peakLimiter()
    @ObservationIgnored private var channels: [AudioChannel] = []
    /// Real-time generators, each in its own format; the bus converts.
    @ObservationIgnored private var sources: [AVAudioNode] = []
    @ObservationIgnored private var buffers: [AnyHashable: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var keepAliveOwners: Set<String> = []
    @ObservationIgnored private var formatObservers: [(AVAudioFormat) -> Void] = []
    @ObservationIgnored private var idleStopTask: Task<Void, Never>?

    /// `offline` renders into memory instead of the speakers; for tests.
    init(masterVolume: Float, offline: Bool = false) {
        self.masterVolume = masterVolume
        format = Self.outputFormat(of: engine)
        if offline {
            try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        }
        engine.attach(masterBus)
        engine.attach(masterLimiter)
        connectMaster()
        engine.mainMixerNode.outputVolume = masterVolume

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    /// Renders the next frames in offline mode; for tests.
    func renderOffline(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard engine.isInManualRenderingMode,
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames),
              (try? engine.renderOffline(frames, to: buffer)) == .success else { return nil }
        return buffer
    }

    /// A widget's sample player with its own volume and voice limit.
    func makeChannel(voices: Int) -> AudioChannel {
        let channel = AudioChannel(engine: engine, voiceCount: voices, output: masterBus, format: format)
        channel.onPlay = { [weak self] in self?.noteActivity() }
        channels.append(channel)
        return channel
    }

    /// Adds a real-time generator (e.g. the spinner's whir) to the master bus.
    /// It keeps its own format; the bus converts. Its volume is its own business.
    func attachSource(_ node: AVAudioNode) {
        engine.attach(node)
        sources.append(node)
        connectSource(node)
    }

    private func connectSource(_ node: AVAudioNode) {
        engine.connect(node, to: masterBus, fromBus: 0, toBus: masterBus.nextAvailableInputBus, format: node.outputFormat(forBus: 0))
    }

    /// A buffer cached under `key` until the output format changes. `make`
    /// receives the current format and renders or decodes into it.
    func buffer(for key: AnyHashable, make: (AVAudioFormat) -> AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        if let cached = buffers[key] { return cached }
        let made = make(format)
        if let made { buffers[key] = made }
        return made
    }

    /// Called after the output sample rate changes and cached buffers were
    /// dropped, so modules holding their own buffers can rebuild them.
    func addFormatObserver(_ observer: @escaping (AVAudioFormat) -> Void) {
        formatObservers.append(observer)
    }

    /// While any owner holds keep-alive, the engine stays running, so the first
    /// sound is not delayed while Bluetooth output wakes up. Otherwise it stops
    /// after a short silence and costs nothing.
    func setKeepAlive(_ enabled: Bool, owner: String) {
        if enabled {
            keepAliveOwners.insert(owner)
            idleStopTask?.cancel()
            startIfNeeded()
        } else {
            keepAliveOwners.remove(owner)
            scheduleIdleStop()
        }
    }

    // MARK: - Lifecycle

    /// Called by channels right before they schedule a sound.
    private func noteActivity() {
        startIfNeeded()
        if keepAliveOwners.isEmpty { scheduleIdleStop() }
    }

    private func startIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            Logger.audio.error("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        guard keepAliveOwners.isEmpty else { return }
        idleStopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard let self, !Task.isCancelled, self.keepAliveOwners.isEmpty else { return }
            self.suspend()
        }
    }

    /// Stops the engine while nothing plays, so an idle app costs nothing.
    func suspend() {
        engine.stop()
        // A stopped engine leaves its players claiming to play; reset them so
        // the next sound starts them again instead of queueing in silence.
        for channel in channels { channel.resetVoices() }
    }

    /// Fired when the output device changes (headphones plugged in, AirPods
    /// connected, sample rate changed). The engine has already stopped itself.
    private func handleConfigurationChange() {
        for channel in channels { channel.resetVoices() }
        let newFormat = Self.outputFormat(of: engine)
        if newFormat.sampleRate != format.sampleRate {
            format = newFormat
            buffers.removeAll()
            connectMaster()
            for channel in channels { channel.reconnect(format: newFormat) }
            for source in sources { connectSource(source) }
            for observer in formatObservers { observer(newFormat) }
        }
        if !keepAliveOwners.isEmpty { startIfNeeded() }
    }

    private func connectMaster() {
        engine.connect(masterBus, to: masterLimiter, format: format)
        engine.connect(masterLimiter, to: engine.mainMixerNode, format: format)
    }

    private static func outputFormat(of engine: AVAudioEngine) -> AVAudioFormat {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        return AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48_000, channels: 2)!
    }
}

extension AVAudioUnitEffect {
    static func peakLimiter() -> AVAudioUnitEffect {
        AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
    }
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Wheedgets"
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let app = Logger(subsystem: subsystem, category: "app")
}
