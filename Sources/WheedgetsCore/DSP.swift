import Foundation

// Small DSP building blocks shared by the synthesizers.

func renderSamples(seconds: Double, sampleRate: Double, _ sample: (Double) -> Double) -> [Float] {
    let count = max(1, Int(seconds * sampleRate))
    var output = [Float](repeating: 0, count: count)
    for index in 0..<count {
        output[index] = Float(sample(Double(index) / sampleRate))
    }
    return output
}

/// Normalizes to the sound's peak level and fades the last 10 ms to zero, so
/// a sound never ends on a click.
func finalizeSamples(_ samples: inout [Float], sampleRate: Double, peak: Float) {
    let maxAmplitude = samples.reduce(Float(0)) { max($0, abs($1)) }
    if maxAmplitude > 0 {
        let gain = peak / maxAmplitude
        for index in samples.indices { samples[index] *= gain }
    }
    let fade = min(samples.count, Int(0.01 * sampleRate))
    guard fade > 0 else { return }
    let start = samples.count - fade
    for offset in 0..<fade {
        samples[start + offset] *= 1 - Float(offset + 1) / Float(fade)
    }
}

/// Phase accumulator in cycles (0..<1).
struct Oscillator {
    private var phase = 0.0

    mutating func sine(_ frequency: Double, _ sampleRate: Double) -> Double {
        sin(2 * .pi * advance(frequency, sampleRate))
    }

    mutating func square(_ frequency: Double, _ sampleRate: Double) -> Double {
        advance(frequency, sampleRate) < 0.5 ? 1 : -1
    }

    private mutating func advance(_ frequency: Double, _ sampleRate: Double) -> Double {
        let current = phase
        phase += frequency / sampleRate
        phase -= phase.rounded(.down)
        return current
    }
}

/// Six inharmonic square waves: the metallic source of the TR-808 hats and cymbals.
struct MetalBank {
    private static let frequencies = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
    private var oscillators = Array(repeating: Oscillator(), count: 6)
    let scale: Double

    init(scale: Double) { self.scale = scale }

    mutating func next(_ sampleRate: Double) -> Double {
        var sum = 0.0
        for index in oscillators.indices {
            sum += oscillators[index].square(Self.frequencies[index] * scale, sampleRate)
        }
        return sum / Double(oscillators.count)
    }
}

/// xorshift64 white noise in -1...1. Seeded, so renders are reproducible.
struct Noise {
    private var state: UInt64

    init(seed: UInt64) {
        state = 0x9E37_79B9_7F4A_7C15 &+ seed &* 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

/// RBJ "Audio EQ Cookbook" biquad, direct form I.
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    private static func coefficients(_ frequency: Double, _ q: Double, _ sampleRate: Double) -> (cos: Double, alpha: Double) {
        // Keep the cutoff below Nyquist at any output sample rate.
        let safeFrequency = min(frequency, sampleRate * 0.45)
        let w0 = 2 * .pi * safeFrequency / sampleRate
        return (cos(w0), sin(w0) / (2 * q))
    }

    static func lowpass(_ frequency: Double, q: Double = 0.707, sampleRate: Double) -> Biquad {
        let (c, alpha) = coefficients(frequency, q, sampleRate)
        return Biquad(b0: (1 - c) / 2, b1: 1 - c, b2: (1 - c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func highpass(_ frequency: Double, q: Double = 0.707, sampleRate: Double) -> Biquad {
        let (c, alpha) = coefficients(frequency, q, sampleRate)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    /// Band-pass with 0 dB peak gain.
    static func bandpass(_ frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let (c, alpha) = coefficients(frequency, q, sampleRate)
        return Biquad(b0: alpha, b1: 0, b2: -alpha, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    /// Takes over another filter's history, so swapping coefficients doesn't click.
    mutating func copyState(from other: Biquad) {
        x1 = other.x1; x2 = other.x2
        y1 = other.y1; y2 = other.y2
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}
