import AVFoundation
import WheedgetsCore

/// One widget's sample player: a `Sampler` feeding the master bus.
///
/// The sampler applies each hit's gain and the channel volume exactly from
/// the first sample; the master limiter keeps volumes above 100 % from
/// clipping. No per-channel mixer or limiter: fewer nodes to render.
@MainActor
final class AudioChannel {
    /// 0…2.
    var volume: Float = 1 {
        didSet { sampler.setVolume(volume.clamped(to: Volume.module)) }
    }

    var onPlay: () -> Void = {}

    private unowned let engine: AVAudioEngine
    private let output: AVAudioMixerNode
    private let sampler: Sampler
    private var node: AVAudioSourceNode?
    private var format: AVAudioFormat

    init(engine: AVAudioEngine, voiceCount: Int, output: AVAudioMixerNode, format: AVAudioFormat) {
        self.engine = engine
        self.output = output
        self.format = format
        sampler = Sampler(maxVoices: voiceCount)
        reconnect(format: format)
    }

    /// Hits overlap freely; past the voice limit the oldest one is cut.
    func play(_ buffer: AVAudioPCMBuffer, gain: Float = 1, pan: Float = 0) {
        onPlay()
        guard engine.isRunning else { return }
        sampler.play(buffer, gain: gain.clamped(to: 0...1), pan: pan.clamped(to: -1...1))
    }

    /// Drops whatever was playing when the engine stopped.
    func resetVoices() {
        sampler.stopAll()
    }

    func reconnect(format: AVAudioFormat) {
        // Buffers are rendered at the output rate, so the sampler node must
        // run at that rate too: replace it when the rate changes.
        if node == nil || format.sampleRate != self.format.sampleRate {
            if let old = node { engine.detach(old) }
            let fresh = sampler.makeNode(format: format)
            engine.attach(fresh)
            node = fresh
        }
        self.format = format
        if let node {
            engine.connect(node, to: output, fromBus: 0, toBus: output.nextAvailableInputBus, format: format)
        }
    }
}
