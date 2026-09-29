import AVFoundation
import os
import WheedgetsCore

/// The spinner's speed and volume, shared with the audio thread.
///
/// The audio thread only tries the lock and keeps the last values if the
/// main thread holds it, so it never waits.
final class SpinnerSpeed: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (speed: 0.0, gain: Float(1)))

    func set(_ speed: Double) {
        lock.withLock { $0.speed = speed }
    }

    /// 0…2; the master limiter keeps boosts from clipping.
    func setGain(_ gain: Float) {
        lock.withLock { $0.gain = gain }
    }

    func current() -> (speed: Double, gain: Float)? {
        lock.withLockIfAvailable { $0 }
    }
}

/// State owned by the render block; touched only on the audio thread.
private final class SpinnerRenderState: @unchecked Sendable {
    var sound: SpinnerSound
    var lastSpeed = 0.0
    var gain: Float = 1

    init(sampleRate: Double) {
        sound = SpinnerSound(sampleRate: sampleRate)
    }
}

enum SpinnerAudio {
    /// A node that synthesizes the whir in real time from `speed`.
    ///
    /// `nonisolated` on purpose: the render block runs on the audio thread, so
    /// it must not be created in (and inherit) the main actor's isolation.
    nonisolated static func makeSourceNode(speed: SpinnerSpeed, sampleRate: Double = 48_000) -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let state = SpinnerRenderState(sampleRate: sampleRate)
        return AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            if let latest = speed.current() {
                state.lastSpeed = latest.speed
                state.gain = latest.gain
            }
            let count = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self),
                  state.sound.renderIfAudible(into: first, count: count, speed: state.lastSpeed) else {
                // At rest: silence costs nothing downstream.
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self).update(repeating: 0, count: count)
                }
                isSilence.pointee = true
                return noErr
            }
            for index in 0..<count { first[index] *= state.gain }
            return noErr
        }
    }
}
