import Foundation

/// Renders the built-in kit into mono float samples.
///
/// The recipes follow classic analog drum machines (TR-808/909 style): pitch-swept
/// sines for kick and toms, filtered noise for snare and clap, and a bank of
/// detuned square waves for the metallic hats and cymbals. Rendering is
/// deterministic, so a sound is identical on every launch.
public enum DrumSynth {
    public static func render(_ sound: DrumSound, sampleRate: Double) -> [Float] {
        var samples: [Float] = switch sound {
        case .kick: kick(sampleRate)
        case .snare: snare(sampleRate)
        case .rim: rim(sampleRate)
        case .clap: clap(sampleRate)
        case .closedHat: hat(sampleRate, decay: 0.022, seconds: 0.15, seed: 5)
        case .openHat: hat(sampleRate, decay: 0.18, seconds: 0.8, seed: 6)
        case .tomHigh: tom(sampleRate, frequency: 220, seed: 7)
        case .tomMid: tom(sampleRate, frequency: 160, seed: 8)
        case .tomLow: tom(sampleRate, frequency: 115, seed: 9)
        case .crash: crash(sampleRate)
        case .ride: ride(sampleRate)
        case .cowbell: cowbell(sampleRate)
        }
        finalizeSamples(&samples, sampleRate: sampleRate, peak: sound.level)
        return samples
    }

    // MARK: - Recipes

    private static func kick(_ sr: Double) -> [Float] {
        var body = Oscillator()
        var noise = Noise(seed: 1)
        var clickFilter = Biquad.lowpass(5_000, sampleRate: sr)
        return renderSamples(seconds: 0.6, sampleRate: sr) { t in
            let frequency = 48 + 120 * exp(-t / 0.03)
            let tone = body.sine(frequency, sr) * exp(-t / 0.2)
            let click = clickFilter.process(noise.next()) * exp(-t / 0.0025) * 0.5
            return tanh(1.8 * (tone + click))
        }
    }

    private static func snare(_ sr: Double) -> [Float] {
        var low = Oscillator(), high = Oscillator()
        var noise = Noise(seed: 2)
        var highpass = Biquad.highpass(1_800, sampleRate: sr)
        var lowpass = Biquad.lowpass(9_000, sampleRate: sr)
        return renderSamples(seconds: 0.35, sampleRate: sr) { t in
            let tone = (0.6 * low.sine(185, sr) + 0.4 * high.sine(330, sr)) * exp(-t / 0.05)
            let wires = lowpass.process(highpass.process(noise.next())) * exp(-t / 0.1)
            return 0.5 * tone + 0.9 * wires
        }
    }

    private static func rim(_ sr: Double) -> [Float] {
        var high = Oscillator(), low = Oscillator()
        var noise = Noise(seed: 3)
        var bandpass = Biquad.bandpass(3_000, q: 1.5, sampleRate: sr)
        return renderSamples(seconds: 0.1, sampleRate: sr) { t in
            let tone = (0.5 * high.sine(1_720, sr) + 0.5 * low.sine(470, sr)) * exp(-t / 0.011)
            let click = bandpass.process(noise.next()) * exp(-t / 0.003)
            return tone + 0.8 * click
        }
    }

    private static func clap(_ sr: Double) -> [Float] {
        var noise = Noise(seed: 4)
        var bandpass = Biquad.bandpass(1_150, q: 1.1, sampleRate: sr)
        // A clap is several hands landing a few milliseconds apart, then room tail.
        let bursts = [0.0, 0.011, 0.023, 0.034]
        let tailStart = bursts[bursts.count - 1]
        return renderSamples(seconds: 0.5, sampleRate: sr) { t in
            var envelope = 0.0
            for start in bursts where t >= start {
                envelope = max(envelope, exp(-(t - start) / 0.0045))
            }
            if t >= tailStart {
                envelope = max(envelope, 0.85 * exp(-(t - tailStart) / 0.13))
            }
            return bandpass.process(noise.next()) * envelope
        }
    }

    private static func hat(_ sr: Double, decay: Double, seconds: Double, seed: UInt64) -> [Float] {
        var metal = MetalBank(scale: 1)
        var noise = Noise(seed: seed)
        var metalBand = Biquad.bandpass(10_000, q: 0.9, sampleRate: sr)
        var metalHigh = Biquad.highpass(7_000, sampleRate: sr)
        var noiseHigh = Biquad.highpass(8_000, sampleRate: sr)
        return renderSamples(seconds: seconds, sampleRate: sr) { t in
            let shimmer = metalHigh.process(metalBand.process(metal.next(sr)))
            let air = noiseHigh.process(noise.next())
            return (0.7 * shimmer + 0.35 * air) * exp(-t / decay)
        }
    }

    private static func tom(_ sr: Double, frequency: Double, seed: UInt64) -> [Float] {
        var body = Oscillator()
        var noise = Noise(seed: seed)
        var lowpass = Biquad.lowpass(2_500, sampleRate: sr)
        return renderSamples(seconds: 0.7, sampleRate: sr) { t in
            let pitch = frequency * (1 + 0.6 * exp(-t / 0.05))
            let tone = body.sine(pitch, sr) * exp(-t / 0.25)
            let stick = lowpass.process(noise.next()) * exp(-t / 0.012) * 0.25
            return tanh(1.4 * (tone + stick))
        }
    }

    private static func crash(_ sr: Double) -> [Float] {
        var metal = MetalBank(scale: 1)
        var noise = Noise(seed: 10)
        var metalBand = Biquad.bandpass(7_000, q: 0.6, sampleRate: sr)
        var metalHigh = Biquad.highpass(5_000, sampleRate: sr)
        var noiseHigh = Biquad.highpass(5_000, sampleRate: sr)
        return renderSamples(seconds: 2.4, sampleRate: sr) { t in
            let shimmer = metalHigh.process(metalBand.process(metal.next(sr)))
            let wash = noiseHigh.process(noise.next())
            return (0.55 * shimmer + 0.6 * wash) * exp(-t / 0.7) + 0.4 * wash * exp(-t / 0.02)
        }
    }

    private static func ride(_ sr: Double) -> [Float] {
        var metal = MetalBank(scale: 1.35)
        var bellLow = Oscillator(), bellHigh = Oscillator()
        var noise = Noise(seed: 11)
        var metalBand = Biquad.bandpass(5_200, q: 1.2, sampleRate: sr)
        var noiseHigh = Biquad.highpass(9_000, sampleRate: sr)
        return renderSamples(seconds: 2.0, sampleRate: sr) { t in
            let shimmer = metalBand.process(metal.next(sr)) * exp(-t / 0.8)
            let bell = (bellLow.sine(2_350, sr) + 0.6 * bellHigh.sine(3_490, sr)) * exp(-t / 0.35) * 0.25
            let air = noiseHigh.process(noise.next()) * exp(-t / 0.5) * 0.12
            return 0.8 * shimmer + bell + air
        }
    }

    private static func cowbell(_ sr: Double) -> [Float] {
        var low = Oscillator(), high = Oscillator()
        var bandpass = Biquad.bandpass(1_000, q: 0.7, sampleRate: sr)
        return renderSamples(seconds: 0.45, sampleRate: sr) { t in
            let tone = 0.5 * low.square(587, sr) + 0.5 * high.square(845, sr)
            let envelope = 0.65 * exp(-t / 0.015) + 0.35 * exp(-t / 0.12)
            return bandpass.process(tone) * envelope
        }
    }
}
