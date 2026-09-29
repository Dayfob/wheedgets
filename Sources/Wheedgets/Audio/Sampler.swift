import AVFoundation
import os

/// A one-shot sampler rendered on the audio thread.
///
/// AVAudioPlayerNode smooths every volume change over ~20 ms, and a drum's
/// whole attack lives in those first milliseconds: a soft hit after a loud
/// one started loud, and a volume change missed the next hit. Here each hit
/// carries its own gain, applied sample-accurately from its first sample, and
/// the channel volume takes effect on the next render cycle.
final class Sampler: @unchecked Sendable {
    /// Buffers are fully rendered before they're played and never written
    /// again, so reading them from the audio thread is safe.
    private struct Trigger: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let gainLeft: Float
        let gainRight: Float
    }

    private struct Voice {
        let buffer: AVAudioPCMBuffer
        let gainLeft: Float
        let gainRight: Float
        var position = 0
    }

    /// Written by the main thread, taken by the audio thread.
    private struct Inbox: Sendable {
        var triggers: [Trigger] = []
        var volume: Float = 1
        var clear = false
    }

    private let inbox = OSAllocatedUnfairLock(initialState: Inbox())
    private let maxVoices: Int

    // Audio-thread state.
    private var voices: [Voice] = []
    private var pending: [Trigger] = []
    private var volume: Float = 1

    init(maxVoices: Int) {
        self.maxVoices = maxVoices
        voices.reserveCapacity(maxVoices + 8)
        pending.reserveCapacity(64)
    }

    // MARK: - Main thread

    /// `pan` is -1…1, balance-style like AVAudioMixer.
    func play(_ buffer: AVAudioPCMBuffer, gain: Float, pan: Float) {
        let trigger = Trigger(buffer: buffer, gainLeft: gain * min(1, 1 - pan), gainRight: gain * min(1, 1 + pan))
        inbox.withLock { $0.triggers.append(trigger) }
    }

    func setVolume(_ volume: Float) {
        inbox.withLock { $0.volume = volume }
    }

    /// Silences everything that is playing.
    func stopAll() {
        inbox.withLock {
            $0.triggers.removeAll()
            $0.clear = true
        }
    }

    /// The node that renders the sampler. `nonisolated`: its block runs on
    /// the audio thread and must not inherit the main actor's isolation.
    nonisolated func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [self] isSilence, _, frameCount, audioBufferList in
            let audible = render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(audioBufferList))
            if !audible { isSilence.pointee = true }
            return noErr
        }
    }

    // MARK: - Audio thread

    /// Returns false when nothing is playing (the buffers are zeroed).
    private func render(frames: Int, into output: UnsafeMutableAudioBufferListPointer) -> Bool {
        // Never wait on the main thread: if it holds the inbox right now,
        // the new hits start on the next cycle, a few milliseconds later.
        inbox.withLockIfAvailable { box in
            if box.clear {
                voices.removeAll(keepingCapacity: true)
                box.clear = false
            }
            volume = box.volume
            pending.append(contentsOf: box.triggers)
            box.triggers.removeAll(keepingCapacity: true)
        }
        for trigger in pending {
            if voices.count >= maxVoices { voices.removeFirst() }
            voices.append(Voice(buffer: trigger.buffer, gainLeft: trigger.gainLeft, gainRight: trigger.gainRight))
        }
        pending.removeAll(keepingCapacity: true)

        guard output.count >= 2,
              let left = output[0].mData?.assumingMemoryBound(to: Float.self),
              let right = output[1].mData?.assumingMemoryBound(to: Float.self) else { return false }
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        guard !voices.isEmpty else { return false }

        var index = 0
        while index < voices.count {
            let voice = voices[index]
            let length = Int(voice.buffer.frameLength)
            let count = min(frames, length - voice.position)
            if count > 0, let source = voice.buffer.floatChannelData {
                let sourceLeft = source[0] + voice.position
                let sourceRight = source[voice.buffer.format.channelCount > 1 ? 1 : 0] + voice.position
                let gainLeft = voice.gainLeft * volume, gainRight = voice.gainRight * volume
                for frame in 0..<count {
                    left[frame] += sourceLeft[frame] * gainLeft
                    right[frame] += sourceRight[frame] * gainRight
                }
            }
            voices[index].position += max(count, 0)
            if voices[index].position >= length {
                voices.remove(at: index)
            } else {
                index += 1
            }
        }
        return true
    }
}
