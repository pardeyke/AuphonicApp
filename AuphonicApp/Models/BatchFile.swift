import Foundation
import AVFoundation

/// Processing status of a single file in the batch
enum BatchFileStatus: Equatable {
    case pending
    case processing(String)     // current step description
    case done(URL)              // output file written
    case failed(String)         // error message
}

/// One audio file loaded into the batch, with the metadata needed for
/// grouping (BWF timecode, channel count) and format-preserving output.
@Observable
final class BatchFile: Identifiable {
    let id = UUID()
    let url: URL
    let channelCount: Int
    let bitDepth: Int
    let isFloat: Bool
    let sampleRate: Double
    let duration: Double            // seconds
    let frameCount: Int64
    let trackNames: [String]        // 0-based, "" for unnamed channels
    let timeReference: UInt64       // bext TimeReference (samples since midnight), 0 if absent
    let hasTimecode: Bool
    let isRF64: Bool

    var status: BatchFileStatus = .pending
    var progress: Double = 0        // 0-1 while processing

    nonisolated init?(url: URL) {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        self.url = url
        self.channelCount = Int(audioFile.fileFormat.channelCount)
        self.sampleRate = audioFile.fileFormat.sampleRate
        self.frameCount = audioFile.length
        self.duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
        self.isRF64 = WavChunkCopier.isRF64(file: url)

        if let info = WavChunkCopier.readFormatInfo(from: url) {
            self.bitDepth = info.bitsPerSample
            self.isFloat = info.isFloat
        } else {
            // Non-WAV or unreadable header: fall back to CoreAudio info
            let desc = audioFile.fileFormat.streamDescription.pointee
            self.bitDepth = desc.mBitsPerChannel > 0 ? Int(desc.mBitsPerChannel) : 24
            self.isFloat = desc.mFormatFlags & kAudioFormatFlagIsFloat != 0
        }

        // iXML track names are indexed by 1-based interleave position; drop index 0
        var names = WavChunkCopier.readIxmlTrackNames(from: url)
        if !names.isEmpty { names.removeFirst() }
        self.trackNames = names

        if let tc = WavChunkCopier.readBextTimeReference(from: url) {
            self.timeReference = tc
            self.hasTimecode = true
        } else {
            self.timeReference = 0
            self.hasTimecode = false
        }
    }

    var fileName: String { url.lastPathComponent }

    /// bext TimeReference as HH:MM:SS (start timecode of the recording)
    var timecodeString: String {
        guard hasTimecode, sampleRate > 0 else { return "--:--:--" }
        let totalSeconds = Int(Double(timeReference) / sampleRate)
        let h = (totalSeconds / 3600) % 24
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

/// A run of files that are adjacent in timecode order and share the same
/// channel count. Processing settings are configured once per group.
@Observable
final class FileGroup: Identifiable {
    let id = UUID()
    let channelCount: Int
    var files: [BatchFile]
    let config: ChannelConfig

    init(channelCount: Int, files: [BatchFile], reusing existingConfig: ChannelConfig? = nil) {
        self.channelCount = channelCount
        self.files = files

        if let existing = existingConfig, existing.fileChannelCount == channelCount {
            // Keep the user's channel selection/settings when files are added or removed
            self.config = existing
        } else {
            let config = ChannelConfig()
            // Some files lack iXML track names; use the first file that has them
            let namedFile = files.first { !$0.trackNames.isEmpty }
            config.configure(
                count: channelCount,
                trackNames: namedFile?.trackNames ?? []
            )
            self.config = config
        }
    }

    var totalDuration: Double {
        files.reduce(0) { $0 + $1.duration }
    }

    var timecodeRangeString: String {
        guard let first = files.first, let last = files.last else { return "" }
        if !first.hasTimecode { return "no timecode" }
        return "\(first.timecodeString)–\(last.timecodeString)"
    }

    var title: String {
        "\(channelCount) ch • \(files.count) file\(files.count == 1 ? "" : "s") • \(timecodeRangeString)"
    }
}

enum FileGrouper {
    /// Sort files by BWF timecode (fallback: file name) and group consecutive
    /// runs that share the same channel count. Configurations of previous
    /// groups are carried over to the new group that contains their files.
    static func makeGroups(from files: [BatchFile], previousGroups: [FileGroup] = []) -> [FileGroup] {
        let sorted = files.sorted { a, b in
            if a.timeReference != b.timeReference {
                return a.timeReference < b.timeReference
            }
            return a.fileName.localizedStandardCompare(b.fileName) == .orderedAscending
        }

        var runs: [[BatchFile]] = []
        var run: [BatchFile] = []
        for file in sorted {
            if let current = run.last, current.channelCount != file.channelCount {
                runs.append(run)
                run = []
            }
            run.append(file)
        }
        if !run.isEmpty { runs.append(run) }

        var availablePrevious = previousGroups
        return runs.map { runFiles in
            let channelCount = runFiles[0].channelCount
            let runIds = Set(runFiles.map(\.id))

            // Reuse the config of a previous group that shares files with this run
            var reused: ChannelConfig?
            if let matchIndex = availablePrevious.firstIndex(where: { previous in
                previous.channelCount == channelCount &&
                previous.files.contains { runIds.contains($0.id) }
            }) {
                reused = availablePrevious.remove(at: matchIndex).config
            }

            return FileGroup(channelCount: channelCount, files: runFiles, reusing: reused)
        }
    }
}
