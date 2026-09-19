import Foundation
import AVFoundation

enum ChannelReplacerError: LocalizedError {
    case rf64NotSupported
    case invalidWav(String)
    case unsupportedSampleFormat(String)
    case processedFileUnreadable(URL)
    case outputEqualsOriginal

    var errorDescription: String? {
        switch self {
        case .rf64NotSupported:
            return "RF64/BW64 files (>4 GB) are not supported yet"
        case .invalidWav(let msg):
            return "Invalid WAV file: \(msg)"
        case .unsupportedSampleFormat(let msg):
            return "Unsupported sample format: \(msg)"
        case .processedFileUnreadable(let url):
            return "Cannot read processed file \(url.lastPathComponent)"
        case .outputEqualsOriginal:
            return "Output path would overwrite the original file"
        }
    }
}

/// Writes processed channels back into an untouched copy of the original file.
///
/// The original is copied byte-for-byte (all metadata chunks, format and
/// untouched channel samples stay bit-perfect), then only the samples of the
/// replaced channels are patched inside the data chunk, converted to the
/// original file's sample format.
enum ChannelReplacer {

    /// - Parameters:
    ///   - original: source multichannel WAV (never modified)
    ///   - output: destination path (must not exist, must differ from original)
    ///   - replacements: processed files mapped to 1-based original channel
    ///     indices, e.g. `([3, 5], stereoFile)` writes the stereo file's left
    ///     channel into channel 3 and its right channel into channel 5.
    static func replaceChannels(
        original: URL,
        output: URL,
        replacements: [(channelIndices: [Int], file: URL)]
    ) throws {
        guard original.standardizedFileURL != output.standardizedFileURL else {
            throw ChannelReplacerError.outputEqualsOriginal
        }
        guard !WavChunkCopier.isRF64(file: original) else {
            throw ChannelReplacerError.rf64NotSupported
        }

        try FileManager.default.copyItem(at: original, to: output)
        do {
            try patchChannels(in: output, replacements: replacements)
        } catch {
            // Don't leave a half-patched output behind
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    // MARK: - Patching

    private struct SampleFormat {
        let bytesPerSample: Int
        let isFloat: Bool
        let bitsPerSample: Int
    }

    private static func patchChannels(
        in output: URL,
        replacements: [(channelIndices: [Int], file: URL)]
    ) throws {
        guard let fmt = WavChunkCopier.readFormatInfo(from: output) else {
            throw ChannelReplacerError.invalidWav("missing fmt chunk")
        }
        guard let dataRange = WavChunkCopier.findChunkRange(in: output, chunkId: "data") else {
            throw ChannelReplacerError.invalidWav("missing data chunk")
        }

        switch (fmt.isFloat, fmt.bitsPerSample) {
        case (false, 16), (false, 24), (false, 32), (true, 32), (true, 64):
            break
        default:
            throw ChannelReplacerError.unsupportedSampleFormat(
                "\(fmt.bitsPerSample)-bit \(fmt.isFloat ? "float" : "PCM")")
        }

        let bytesPerSample = fmt.bitsPerSample / 8
        let blockAlign = fmt.blockAlign
        guard blockAlign >= bytesPerSample * fmt.channels, fmt.channels > 0 else {
            throw ChannelReplacerError.invalidWav("inconsistent block alignment")
        }
        let sampleFormat = SampleFormat(
            bytesPerSample: bytesPerSample,
            isFloat: fmt.isFloat,
            bitsPerSample: fmt.bitsPerSample
        )

        let totalFrames = Int64(dataRange.size) / Int64(blockAlign)

        // Open all processed sources
        struct Source {
            let file: AVAudioFile
            let buffer: AVAudioPCMBuffer
            let destChannels: [Int]     // 1-based channel indices in output
        }
        let chunkFrames: AVAudioFrameCount = 1 << 18    // 256k frames per pass

        var sources: [Source] = []
        for replacement in replacements {
            guard let file = try? AVAudioFile(forReading: replacement.file),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: chunkFrames) else {
                throw ChannelReplacerError.processedFileUnreadable(replacement.file)
            }
            for ch in replacement.channelIndices {
                guard ch >= 1, ch <= fmt.channels else {
                    throw ChannelReplacerError.invalidWav("channel \(ch) out of range")
                }
            }
            sources.append(Source(file: file, buffer: buffer,
                                  destChannels: replacement.channelIndices))
        }

        let handle = try FileHandle(forUpdating: output)
        defer { try? handle.close() }

        var frameStart: Int64 = 0
        while frameStart < totalFrames {
            let framesInRegion = Int(min(Int64(chunkFrames), totalFrames - frameStart))
            let regionOffset = dataRange.offset + UInt64(frameStart) * UInt64(blockAlign)
            let regionLength = framesInRegion * blockAlign

            try handle.seek(toOffset: regionOffset)
            guard var region = try handle.read(upToCount: regionLength),
                  region.count == regionLength else {
                throw ChannelReplacerError.invalidWav("data chunk truncated")
            }

            for source in sources {
                source.buffer.frameLength = 0
                // Sources may be shorter than the original; remaining frames become silence
                try? source.file.read(into: source.buffer,
                                      frameCount: AVAudioFrameCount(framesInRegion))
                let framesRead = Int(source.buffer.frameLength)
                guard let channelData = source.buffer.floatChannelData else { continue }
                let sourceChannelCount = Int(source.buffer.format.channelCount)

                region.withUnsafeMutableBytes { raw in
                    for (srcCh, destCh) in source.destChannels.enumerated() {
                        let srcSamples = channelData[min(srcCh, sourceChannelCount - 1)]
                        let channelByteOffset = (destCh - 1) * bytesPerSample
                        for frame in 0..<framesInRegion {
                            let sample: Float = frame < framesRead ? srcSamples[frame] : 0
                            let byteOffset = frame * blockAlign + channelByteOffset
                            store(sample: sample, into: raw, at: byteOffset, format: sampleFormat)
                        }
                    }
                }
            }

            try handle.seek(toOffset: regionOffset)
            try handle.write(contentsOf: region)

            frameStart += Int64(framesInRegion)
        }
    }

    /// Convert a float sample to the output file's sample format and store it (little-endian)
    private static func store(
        sample: Float,
        into raw: UnsafeMutableRawBufferPointer,
        at offset: Int,
        format: SampleFormat
    ) {
        if format.isFloat {
            if format.bitsPerSample == 32 {
                raw.storeBytes(of: sample.bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
            } else {
                raw.storeBytes(of: Double(sample).bitPattern.littleEndian, toByteOffset: offset, as: UInt64.self)
            }
            return
        }

        switch format.bitsPerSample {
        case 16:
            let scaled = (Double(sample) * 32768.0).rounded()
            let value = Int16(clamping: Int64(scaled.clamped(to: -32768...32767)))
            raw.storeBytes(of: UInt16(bitPattern: value).littleEndian, toByteOffset: offset, as: UInt16.self)
        case 24:
            let scaled = (Double(sample) * 8_388_608.0).rounded()
            let value = Int32(scaled.clamped(to: -8_388_608...8_388_607))
            let bits = UInt32(bitPattern: value)
            raw.storeBytes(of: UInt8(bits & 0xFF), toByteOffset: offset, as: UInt8.self)
            raw.storeBytes(of: UInt8((bits >> 8) & 0xFF), toByteOffset: offset + 1, as: UInt8.self)
            raw.storeBytes(of: UInt8((bits >> 16) & 0xFF), toByteOffset: offset + 2, as: UInt8.self)
        default: // 32-bit int
            let scaled = (Double(sample) * 2_147_483_648.0).rounded()
            let value = Int32(clamping: Int64(scaled.clamped(to: -2_147_483_648...2_147_483_647)))
            raw.storeBytes(of: UInt32(bitPattern: value).littleEndian, toByteOffset: offset, as: UInt32.self)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
