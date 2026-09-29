import AVFoundation
import Testing
@testable import Wheedgets
@testable import WheedgetsCore

@MainActor
struct AudioGraphTests {
    private func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[channel][frame])) }
        }
        return peak
    }

    private func hit(channelIndex: Int, of count: Int) throws -> Float {
        let engine = AudioEngine(masterVolume: 1, offline: true)
        let channels = (0..<count).map { _ in engine.makeChannel(voices: 4) }
        let sound = try #require(SampleDecoder.buffer(
            mono: DrumSynth.render(.snare, sampleRate: engine.format.sampleRate),
            format: engine.format
        ))
        channels[channelIndex].play(sound)
        let output = try #require(engine.renderOffline(frames: 4_096))
        return peak(output)
    }

    /// The engine stops after idle time; the next hit must still be heard.
    @Test func soundsPlayAgainAfterTheEngineWasSuspended() throws {
        let engine = AudioEngine(masterVolume: 1, offline: true)
        let channel = engine.makeChannel(voices: 1)
        let sound = try #require(SampleDecoder.buffer(
            mono: DrumSynth.render(.snare, sampleRate: engine.format.sampleRate),
            format: engine.format
        ))
        channel.play(sound)
        _ = engine.renderOffline(frames: 4_096)
        engine.suspend()

        channel.play(sound)
        let output = try #require(engine.renderOffline(frames: 4_096))
        #expect(peak(output) > 0.1)
    }

    /// The spinner's real-time generator runs on the audio thread.
    @Test func spinnerWhirReachesTheOutput() throws {
        let engine = AudioEngine(masterVolume: 1, offline: true)
        let speed = SpinnerSpeed()
        engine.attachSource(SpinnerAudio.makeSourceNode(speed: speed))
        speed.set(25)
        engine.setKeepAlive(true, owner: "test")

        var loudest: Float = 0
        for _ in 0..<30 {
            if let output = engine.renderOffline(frames: 4_096) { loudest = max(loudest, peak(output)) }
        }
        #expect(loudest > 0.05)
    }

    @Test func aSingleChannelReachesTheOutput() throws {
        #expect(try hit(channelIndex: 0, of: 1) > 0.1)
    }

    @Test(arguments: [0, 1])
    func everyChannelReachesTheOutputWhenSeveralExist(index: Int) throws {
        #expect(try hit(channelIndex: index, of: 2) > 0.1)
    }
}
