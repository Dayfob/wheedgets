import AVFoundation
import Testing
@testable import Wheedgets
@testable import WheedgetsCore

/// Drum hits must get their exact gain from their very first sample.
@MainActor
struct SampleAccurateGainTests {
    private func firstSamples(after setup: (AudioChannel, AVAudioPCMBuffer) -> Void, engine: AudioEngine) throws -> [Float] {
        var samples: [Float] = []
        for _ in 0..<3 {
            let b = try #require(engine.renderOffline(frames: 1_024))
            samples += Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: 1_024))
        }
        let start = try #require(samples.firstIndex { abs($0) > 0.0001 })
        return Array(samples[start..<(start + 64)])
    }

    @Test func aSoftHitAfterALoudOneStartsSoft() throws {
        let engine = AudioEngine(masterVolume: 1, offline: true)
        let channel = engine.makeChannel(voices: 1)
        let sound = try #require(SampleDecoder.buffer(mono: [Float](repeating: 0.5, count: 4_800), format: engine.format))
        channel.play(sound, gain: 1)
        for _ in 0..<5 { _ = engine.renderOffline(frames: 4_096) }

        channel.play(sound, gain: 0.2)
        let attack = try firstSamples(after: { _, _ in }, engine: engine)
        #expect(attack.allSatisfy { abs($0 - 0.1) < 0.002 }, "attack at 0.1 from the first sample: \(attack.prefix(4))")
    }

    @Test func aVolumeChangeAppliesToTheNextHitsAttack() throws {
        let engine = AudioEngine(masterVolume: 1, offline: true)
        let channel = engine.makeChannel(voices: 2)
        let sound = try #require(SampleDecoder.buffer(mono: [Float](repeating: 0.5, count: 4_800), format: engine.format))
        channel.play(sound)
        for _ in 0..<5 { _ = engine.renderOffline(frames: 4_096) }

        channel.volume = 0.25
        channel.play(sound)
        let attack = try firstSamples(after: { _, _ in }, engine: engine)
        #expect(attack.allSatisfy { abs($0 - 0.125) < 0.002 }, "\(attack.prefix(4))")
    }
}
