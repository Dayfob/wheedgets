import Testing
@testable import WheedgetsCore

struct DrumSynthTests {
    @Test(arguments: DrumSound.allCases)
    func rendersBalancedClickFreeBuffer(sound: DrumSound) {
        let samples = DrumSynth.render(sound, sampleRate: 48_000)
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }

        #expect(samples.count > 1_000)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(abs(peak - sound.level) < 0.001, "normalized to the sound's level")
        #expect(abs(samples[samples.count - 1]) < 0.0001, "ends on silence, no click")
    }

    @Test func renderingIsDeterministic() {
        #expect(DrumSynth.render(.snare, sampleRate: 48_000) == DrumSynth.render(.snare, sampleRate: 48_000))
    }

    @Test(arguments: [22_050.0, 44_100, 96_000])
    func survivesOtherSampleRates(rate: Double) {
        // Filter cutoffs above Nyquist would blow up; the synth clamps them.
        for sound in DrumSound.allCases {
            #expect(DrumSynth.render(sound, sampleRate: rate).allSatisfy { $0.isFinite })
        }
    }
}
