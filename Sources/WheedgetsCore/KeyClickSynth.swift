import Foundation

/// Synthesized mechanical keyboard sounds, so keyboard sounds work out of the
/// box without shipping recordings.
///
/// A key press is modeled as the switch mechanism (a click for clicky
/// switches) followed by the keycap bottoming out: a short noise burst ringing
/// through the case resonance plus a low body thump. The release is a lighter,
/// higher-pitched version. Long stabilized keys ring lower and rattle.
public enum KeyClickSynth {
    public enum Profile: String, CaseIterable, Codable, Sendable {
        /// Tactile clicky switches (Blue-style): bright and sharp.
        case clicky
        /// Lubed linear switches: deep, muted "thock".
        case thocky
    }

    public enum Kind: Hashable, Sendable {
        case regular(variant: Int)
        case space
        case enter
        case backspace
        case modifier
    }

    public struct Sound: Hashable, Sendable {
        public var profile: Profile
        public var kind: Kind
        public var phase: KeySoundPack.Phase
    }

    public static let variantCount = 4

    /// A complete pack for the profile, covering every key macOS reports.
    public static func pack(_ profile: Profile, name: String) -> KeySoundPack {
        var press: [Int: [KeySoundPack.Clip]] = [:]
        var release: [Int: [KeySoundPack.Clip]] = [:]
        for code in MechvibesKeyCodes.allCodes {
            let kinds = kinds(for: code)
            press[code] = kinds.map { .synth(Sound(profile: profile, kind: $0, phase: .press)) }
            release[code] = kinds.map { .synth(Sound(profile: profile, kind: $0, phase: .release)) }
        }
        return KeySoundPack(name: name, press: press, release: release)
    }

    private static func kinds(for code: Int) -> [Kind] {
        switch code {
        case MechvibesKeyCodes.space: [.space]
        case MechvibesKeyCodes.enter, MechvibesKeyCodes.keypadEnter: [.enter]
        case MechvibesKeyCodes.backspace: [.backspace]
        case _ where MechvibesKeyCodes.modifiers.contains(code): [.modifier]
        default: (0..<variantCount).map { .regular(variant: $0) }
        }
    }

    public static func render(_ sound: Sound, sampleRate sr: Double) -> [Float] {
        let isClicky = sound.profile == .clicky
        let isRelease = sound.phase == .release

        // Case resonance and body pitch: clicky is bright, thocky is deep.
        var resonance = isClicky ? 2_400.0 : 900.0
        var body = isClicky ? 330.0 : 170.0
        var decay = isClicky ? 0.018 : 0.028
        var rattle = false
        var seed: UInt64 = isClicky ? 100 : 200

        switch sound.kind {
        case .regular(let variant):
            // Each variant is a slightly different key: small pitch spread.
            let spread = [1.0, 0.94, 1.06, 0.97][variant % 4]
            resonance *= spread
            body *= spread
            seed += UInt64(variant)
        case .space:
            resonance *= 0.55; body *= 0.7; decay *= 1.8; rattle = true; seed += 10
        case .enter, .backspace:
            resonance *= 0.7; body *= 0.8; decay *= 1.5; rattle = true; seed += 20
        case .modifier:
            resonance *= 0.85; body *= 0.9; seed += 30
        }

        if isRelease {
            resonance *= 1.35
            body *= 1.2
            decay *= 0.6
            seed += 1_000
        }

        // Clicky switches click during travel, a few ms before bottoming out.
        let clickTime = isClicky && !isRelease ? 0.0 : -1
        let impactTime = isClicky && !isRelease ? 0.009 : 0.0
        let rattleTime = impactTime + 0.012

        var noise = Noise(seed: seed)
        var ring = Biquad.bandpass(resonance, q: 3.5, sampleRate: sr)
        var clickFilter = Biquad.bandpass(4_800, q: 2, sampleRate: sr)
        var rattleFilter = Biquad.bandpass(resonance * 1.8, q: 4, sampleRate: sr)
        var thump = Oscillator()

        var samples = renderSamples(seconds: rattle ? 0.14 : 0.09, sampleRate: sr) { t in
            let white = noise.next()
            var out = 0.0
            if clickTime >= 0, t >= clickTime {
                out += clickFilter.process(white) * exp(-(t - clickTime) / 0.0015) * 1.6
            }
            if t >= impactTime {
                let local = t - impactTime
                let burst = exp(-local / 0.0012)
                out += ring.process(white * burst) * 6 * exp(-local / decay)
                out += thump.sine(body, sr) * exp(-local / (decay * 0.8)) * 0.35
            }
            if rattle, t >= rattleTime {
                out += rattleFilter.process(white) * exp(-(t - rattleTime) / 0.01) * 0.5
            }
            return out
        }
        finalizeSamples(&samples, sampleRate: sr, peak: isRelease ? 0.4 : 0.8)
        return samples
    }
}
