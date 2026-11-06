import AVFoundation
import CoreMedia
import Speech

/// Reads a recording's sound in the speech engine's format, one buffer at a time, as the engine asks.
/// Uses the audio mix of every sound track, so a meeting recording with the microphone and the
/// other people on separate tracks loses nobody. A long file never piles up in memory.
final class AudioFileSequence: AsyncSequence, @unchecked Sendable {
    typealias Element = AnalyzerInput

    enum ReadError: LocalizedError {
        case noSound
        case unreadable(String)  // the system's reason, kept for debugging; people see plain English

        var errorDescription: String? {
            switch self {
            case .noSound: return "This file has no sound to transcribe."
            case .unreadable: return "Recap couldn't read this file. It may be damaged, cut off part way, or not really an audio or video file."
            }
        }
    }

    let duration: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var _position: Double = 0
    private var _failure: Error?

    /// Seconds of audio handed to the engine so far.
    var position: Double { lock.withLock { _position } }
    /// Set when reading stopped because of an error rather than the end of the file.
    var failure: Error? { lock.withLock { _failure } }

    init(url: URL, format: AVAudioFormat) async throws {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let length: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
            length = try await asset.load(.duration)
        } catch {
            throw ReadError.unreadable(error.localizedDescription)
        }
        guard !tracks.isEmpty else { throw ReadError.noSound }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ReadError.unreadable(error.localizedDescription) }

        // Interleaved linear PCM at the engine's rate, channel count and sample type.
        let isFloat = format.commonFormat == .pcmFormatFloat32 || format.commonFormat == .pcmFormatFloat64
        let bits: Int
        switch format.commonFormat {
        case .pcmFormatInt16: bits = 16
        case .pcmFormatInt32, .pcmFormatFloat32: bits = 32
        case .pcmFormatFloat64: bits = 64
        default: bits = 32
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ReadError.unreadable("The sound format isn't supported.") }
        reader.add(output)
        guard reader.startReading() else {
            throw ReadError.unreadable(reader.error?.localizedDescription ?? "The file may be damaged.")
        }
        guard let interleaved = AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate,
                                              channels: format.channelCount, interleaved: true) else {
            throw ReadError.unreadable("The sound format isn't supported.")
        }
        self.reader = reader
        self.output = output
        self.format = interleaved
        self.duration = length.isNumeric ? Swift.max(0, length.seconds) : 0
    }

    func cancel() {
        reader.cancelReading()
    }

    func makeAsyncIterator() -> Iterator { Iterator(source: self) }

    struct Iterator: AsyncIteratorProtocol {
        let source: AudioFileSequence
        mutating func next() async throws -> AnalyzerInput? {
            try Task.checkCancellation()
            return try source.nextInput()
        }
    }

    private func recordFailure(_ why: String) -> Error {
        let error = ReadError.unreadable(why)
        lock.withLock { _failure = error }
        reader.cancelReading()
        return error
    }

    private func nextInput() throws -> AnalyzerInput? {
        while true {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    let error = ReadError.unreadable(reader.error?.localizedDescription ?? "Reading stopped part way through.")
                    lock.withLock { _failure = error }
                    throw error
                }
                return nil
            }
            let count = CMSampleBufferGetNumSamples(sample)
            if count == 0 { continue }
            // A gap in the audio must fail the job, never save a transcript with part of it missing.
            guard count > 0, count <= Int(Int32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw recordFailure("A part of the sound couldn't be read.")
            }
            let frames = AVAudioFrameCount(count)
            buffer.frameLength = frames
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count),
                                                                      into: buffer.mutableAudioBufferList)
            guard status == noErr else { throw recordFailure("A part of the sound couldn't be converted (\(status)).") }
            let start = CMSampleBufferGetPresentationTimeStamp(sample)
            let end = start.seconds + Double(frames) / format.sampleRate
            lock.withLock { if end.isFinite { _position = end } }
            return AnalyzerInput(buffer: buffer, bufferStartTime: start.isNumeric ? start : nil)
        }
    }
}
