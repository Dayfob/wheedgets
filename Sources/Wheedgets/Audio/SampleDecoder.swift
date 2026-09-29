import AVFoundation
import OSLog

/// Decodes a user's sample file into the engine's stereo float format.
enum SampleDecoder {
    /// Drum samples are truncated: a pad is a one-shot, not a music player.
    static let padMaxDuration: Double = 10

    /// Decodes into `target`. `maxDuration` nil reads the whole file.
    static func load(_ url: URL, as target: AVAudioFormat, maxDuration: Double? = padMaxDuration) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            let source = file.processingFormat
            let limit = maxDuration.map { $0 * source.sampleRate } ?? Double(file.length)
            let frames = AVAudioFrameCount(min(Double(file.length), limit))
            guard frames > 0,
                  let decoded = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return nil }
            try file.read(into: decoded, frameCount: frames)
            guard let resampled = resample(decoded, to: target.sampleRate) else { return nil }
            return toStereo(resampled, format: target)
        } catch {
            Logger.audio.error("Could not load sample \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Copies mono samples into every channel of a buffer in `format`.
    static func buffer(mono samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            for channel in 0..<Int(format.channelCount) {
                channels[channel].update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }

    /// Copies `[start, start + duration)` out of a decoded buffer.
    static func slice(_ buffer: AVAudioPCMBuffer, startMs: Double, durationMs: Double) -> AVAudioPCMBuffer? {
        let rate = buffer.format.sampleRate
        let start = Int(startMs / 1_000 * rate)
        let end = min(Int(buffer.frameLength), start + Int(durationMs / 1_000 * rate))
        guard start >= 0, end > start,
              let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(end - start)),
              let source = buffer.floatChannelData,
              let destination = output.floatChannelData else { return nil }
        output.frameLength = AVAudioFrameCount(end - start)
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel].advanced(by: start), count: end - start)
        }
        return output
    }

    /// Validates a file before it is imported into the library.
    static func canDecode(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }

    /// Converts to deinterleaved float at the target rate, keeping the channel count.
    private static func resample(_ input: AVAudioPCMBuffer, to sampleRate: Double) -> AVAudioPCMBuffer? {
        let channels = input.format.channelCount
        guard let intermediate = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else { return nil }
        if input.format == intermediate { return input }
        guard let converter = AVAudioConverter(from: input.format, to: intermediate) else { return nil }

        let ratio = sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: intermediate, frameCapacity: capacity) else { return nil }

        let feed = OneShotFeed(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            feed.next(inputStatus)
        }
        guard status != .error else {
            Logger.audio.error("Sample conversion failed: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        return output
    }

    /// Mono is duplicated to both sides; more than two channels keep the first two.
    private static func toStereo(_ input: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: input.frameLength),
              let source = input.floatChannelData,
              let destination = output.floatChannelData else { return nil }
        output.frameLength = input.frameLength
        let count = Int(input.frameLength)
        let sourceChannels = Int(input.format.channelCount)
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[min(channel, sourceChannels - 1)], count: count)
        }
        return output
    }
}

/// Hands the converter the decoded buffer exactly once, then reports end of stream.
/// The converter calls back synchronously inside `convert`, so this never races.
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .endOfStream
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
