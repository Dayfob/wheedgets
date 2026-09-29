import Foundation

/// Real-time sound of a spinning fidget spinner, driven by its speed.
///
/// Slow, you hear each arm sweep past as a "whoosh"; fast, the sweeps merge
/// into a whir with a hum at the arm-pass frequency, plus the fine hiss of
/// the ball bearing. Runs on the audio thread: no allocation, no locks.
public struct SpinnerSound: Sendable {
    private let sampleRate: Double
    private var noise = Noise(seed: 77)
    private var whoosh: Biquad
    private var bearing: Biquad
    private var armPhase = 0.0
    private var humPhase = 0.0
    private var smoothedSpeed = 0.0
    private var framesUntilRetune = 0
    private let arms = 3.0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        whoosh = .bandpass(700, q: 1.2, sampleRate: sampleRate)
        bearing = .highpass(4_000, sampleRate: sampleRate)
    }

    /// At rest the whir is silent: skip the synthesis entirely. Returns false
    /// (and leaves `output` untouched) when there's nothing to hear.
    public mutating func renderIfAudible(into output: UnsafeMutablePointer<Float>, count: Int, speed: Double) -> Bool {
        if abs(speed) < 0.01 && smoothedSpeed < 0.02 {
            smoothedSpeed = 0
            return false
        }
        render(into: output, count: count, speed: speed)
        return true
    }

    /// Fills `count` mono samples for a spinner turning at `speed` rev/s.
    public mutating func render(into output: UnsafeMutablePointer<Float>, count: Int, speed: Double) {
        let target = abs(speed)
        for index in 0..<count {
            // Glide toward the target so speed changes never click.
            smoothedSpeed += (target - smoothedSpeed) * 0.0015
            let revs = smoothedSpeed

            if framesUntilRetune <= 0 {
                // Faster spin, brighter air.
                whoosh = whoosh.retuned(bandpass: 500 + revs * 45, q: 1.2, sampleRate: sampleRate)
                framesUntilRetune = 64
            }
            framesUntilRetune -= 1

            let armRate = revs * arms
            armPhase = (armPhase + armRate / sampleRate).truncatingRemainder(dividingBy: 1)
            humPhase = (humPhase + armRate / sampleRate).truncatingRemainder(dividingBy: 1)

            let white = noise.next()
            // Each arm pass is a puff of air; at speed they blur into a steady whir.
            let pulse = 0.5 + 0.5 * cos(2 * .pi * armPhase)
            let pulseDepth = min(1, 6 / max(armRate, 1))
            let air = whoosh.process(white) * (1 - pulseDepth + pulseDepth * pulse * pulse)
            let hum = sin(2 * .pi * humPhase) * min(1, revs / 25) * 0.25
            let hiss = bearing.process(white) * 0.08

            let loudness = pow(min(1, revs / 18), 0.7)
            output[index] = Float((air * 2.2 + hum + hiss) * loudness * 0.6)
        }
    }
}

extension Biquad {
    /// New coefficients with the filter's history kept, so retuning is seamless.
    func retuned(bandpass frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        var tuned = Biquad.bandpass(frequency, q: q, sampleRate: sampleRate)
        tuned.copyState(from: self)
        return tuned
    }
}
