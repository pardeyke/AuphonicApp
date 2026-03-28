import Foundation
import AVFoundation

enum WavChunkCopier {

    // MARK: - Read Chunks

    static func readChunk(from file: URL, chunkId: String) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 12),
              headerData.count == 12 else { return nil }

        let riffId = String(data: headerData[0..<4], encoding: .ascii)
        guard riffId == "RIFF" else { return nil }

        var offset: UInt64 = 12
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0

        while offset < fileSize - 8 {
            handle.seek(toFileOffset: offset)
            guard let chunkHeader = try? handle.read(upToCount: 8),
                  chunkHeader.count == 8 else { break }

            let id = String(data: chunkHeader[0..<4], encoding: .ascii) ?? ""
            let size = chunkHeader.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: 4, as: UInt32.self)
            }

            if id == chunkId {
                guard let chunkData = try? handle.read(upToCount: Int(size)) else { return nil }
                return chunkData
            }

            offset += 8 + UInt64(size)
            if size % 2 != 0 { offset += 1 } // padding
        }
        return nil
    }

    static func readIxmlChunk(from file: URL) -> Data? {
        readChunk(from: file, chunkId: "iXML")
    }

    static func readIxmlTrackNames(from file: URL) -> [String] {
        guard let ixmlData = readIxmlChunk(from: file),
              let xmlString = String(data: ixmlData, encoding: .utf8) else {
            return []
        }

        let parser = IXMLTrackParser(xml: xmlString)
        return parser.trackNames
    }

    // MARK: - Write Chunks

    static func writeChunk(to file: URL, chunkId: String, data chunkData: Data) -> Bool {
        guard let handle = try? FileHandle(forUpdating: file) else { return false }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 12),
              headerData.count == 12 else { return false }

        let riffId = String(data: headerData[0..<4], encoding: .ascii)
        guard riffId == "RIFF" else { return false }

        var riffSize = headerData.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 4, as: UInt32.self)
        }

        // Try to find and replace existing chunk
        var offset: UInt64 = 12
        let fileEnd: UInt64 = 8 + UInt64(riffSize)

        while offset < fileEnd {
            handle.seek(toFileOffset: offset)
            guard let chunkHeader = try? handle.read(upToCount: 8),
                  chunkHeader.count == 8 else { break }

            let id = String(data: chunkHeader[0..<4], encoding: .ascii) ?? ""
            let existingSize = chunkHeader.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: 4, as: UInt32.self)
            }

            if id == chunkId {
                // Replace existing chunk: remove old, write new
                let oldChunkTotalSize = 8 + UInt64(existingSize) + (existingSize % 2 != 0 ? 1 : 0)
                let afterChunkOffset = offset + oldChunkTotalSize

                handle.seek(toFileOffset: afterChunkOffset)
                let remainingData = handle.readDataToEndOfFile()

                handle.seek(toFileOffset: offset)
                handle.truncateFile(atOffset: offset)

                // Write new chunk
                writeChunkHeader(to: handle, id: chunkId, size: UInt32(chunkData.count))
                handle.write(chunkData)
                if chunkData.count % 2 != 0 { handle.write(Data([0])) }

                handle.write(remainingData)

                // Update RIFF size
                let sizeDiff = Int64(chunkData.count) - Int64(existingSize)
                riffSize = UInt32(Int64(riffSize) + sizeDiff)
                handle.seek(toFileOffset: 4)
                var sizeLE = riffSize.littleEndian
                handle.write(Data(bytes: &sizeLE, count: 4))
                return true
            }

            var nextOffset = offset + 8 + UInt64(existingSize)
            if existingSize % 2 != 0 { nextOffset += 1 }
            offset = nextOffset
        }

        // Chunk not found — append
        handle.seekToEndOfFile()
        writeChunkHeader(to: handle, id: chunkId, size: UInt32(chunkData.count))
        handle.write(chunkData)
        if chunkData.count % 2 != 0 { handle.write(Data([0])) }

        riffSize += UInt32(8 + chunkData.count + (chunkData.count % 2 != 0 ? 1 : 0))
        handle.seek(toFileOffset: 4)
        var sizeLE = riffSize.littleEndian
        handle.write(Data(bytes: &sizeLE, count: 4))
        return true
    }

    static func removeChunk(from file: URL, chunkId: String) -> Bool {
        guard let handle = try? FileHandle(forUpdating: file) else { return false }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 12),
              headerData.count == 12 else { return false }

        var riffSize = headerData.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 4, as: UInt32.self)
        }

        var offset: UInt64 = 12
        let fileEnd: UInt64 = 8 + UInt64(riffSize)

        while offset < fileEnd {
            handle.seek(toFileOffset: offset)
            guard let chunkHeader = try? handle.read(upToCount: 8),
                  chunkHeader.count == 8 else { break }

            let id = String(data: chunkHeader[0..<4], encoding: .ascii) ?? ""
            let chunkSize = chunkHeader.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: 4, as: UInt32.self)
            }

            if id == chunkId {
                let totalChunkSize = 8 + UInt64(chunkSize) + (chunkSize % 2 != 0 ? 1 : 0)
                let afterChunk = offset + totalChunkSize

                handle.seek(toFileOffset: afterChunk)
                let remaining = handle.readDataToEndOfFile()

                handle.seek(toFileOffset: offset)
                handle.truncateFile(atOffset: offset)
                handle.write(remaining)

                riffSize -= UInt32(totalChunkSize)
                handle.seek(toFileOffset: 4)
                var sizeLE = riffSize.littleEndian
                handle.write(Data(bytes: &sizeLE, count: 4))
                return true
            }

            var nextOffset = offset + 8 + UInt64(chunkSize)
            if chunkSize % 2 != 0 { nextOffset += 1 }
            offset = nextOffset
        }

        return true // chunk not found is not an error
    }

    // MARK: - WAV Bit Depth

    static func readWavBitDepth(from file: URL) -> Int {
        guard let fmtData = readChunk(from: file, chunkId: "fmt "),
              fmtData.count >= 16 else { return 0 }

        let bitsPerSample = fmtData.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 14, as: UInt16.self)
        }
        return Int(bitsPerSample)
    }

    // MARK: - Downgrade WaveFormatExtensible to PCM

    /// Rewrites a WaveFormatExtensible fmt chunk (tag 0xFFFE, 40 bytes) to a simple
    /// WAVE_FORMAT_PCM fmt chunk (tag 0x0001, 16 bytes), shrinking the RIFF accordingly.
    /// No-op if the file is already PCM format.
    @discardableResult
    static func downgradeToSimplePcm(file: URL) -> Bool {
        guard let fmtData = readChunk(from: file, chunkId: "fmt "),
              fmtData.count >= 18 else { return false }

        let formatTag = fmtData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self) }
        guard formatTag == 0xFFFE else { return true } // already simple PCM, nothing to do

        // Extract the basic 16-byte PCM fields from the existing fmt chunk
        let channels = fmtData.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) }
        let sampleRate = fmtData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let bitsPerSample = fmtData.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt16.self) }
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        // Build 16-byte PCM fmt chunk data
        var pcmFmt = Data(count: 16)
        pcmFmt.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt16(1).littleEndian, toByteOffset: 0, as: UInt16.self)          // format tag = PCM
            ptr.storeBytes(of: channels.littleEndian, toByteOffset: 2, as: UInt16.self)           // channels
            ptr.storeBytes(of: sampleRate.littleEndian, toByteOffset: 4, as: UInt32.self)         // sample rate
            ptr.storeBytes(of: byteRate.littleEndian, toByteOffset: 8, as: UInt32.self)           // byte rate
            ptr.storeBytes(of: blockAlign.littleEndian, toByteOffset: 12, as: UInt16.self)        // block align
            ptr.storeBytes(of: bitsPerSample.littleEndian, toByteOffset: 14, as: UInt16.self)     // bits per sample
        }

        return writeChunk(to: file, chunkId: "fmt ", data: pcmFmt)
    }

    // MARK: - iXML Update

    static func updateIxmlForOutput(ixmlData: Data, outputBitDepth: Int, extractedChannel: Int) -> Data {
        guard var xmlString = String(data: ixmlData, encoding: .utf8) else { return ixmlData }

        // Update bit depth
        if let range = xmlString.range(of: "<AUDIO_BIT_DEPTH>[^<]*</AUDIO_BIT_DEPTH>", options: .regularExpression) {
            xmlString.replaceSubrange(range, with: "<AUDIO_BIT_DEPTH>\(outputBitDepth)</AUDIO_BIT_DEPTH>")
        }

        if extractedChannel > 0 {
            // Single channel extracted — update counts and keep only that track
            updateIxmlTag(&xmlString, tag: "CHANNEL_COUNT", value: "1")
            updateIxmlTag(&xmlString, tag: "TRACK_COUNT", value: "1")
            filterIxmlTracks(&xmlString, keepInterleaveIndices: [extractedChannel])
        } else if extractedChannel == -1 {
            // L+R (first two channels)
            updateIxmlTag(&xmlString, tag: "CHANNEL_COUNT", value: "2")
            updateIxmlTag(&xmlString, tag: "TRACK_COUNT", value: "2")
            filterIxmlTracks(&xmlString, keepInterleaveIndices: [1, 2])
        }

        return xmlString.data(using: .utf8) ?? ixmlData
    }

    /// Update a simple iXML tag value, or insert it inside BWFXML if not found
    private static func updateIxmlTag(_ xml: inout String, tag: String, value: String) {
        let pattern = "<\(tag)>[^<]*</\(tag)>"
        if let range = xml.range(of: pattern, options: .regularExpression) {
            xml.replaceSubrange(range, with: "<\(tag)>\(value)</\(tag)>")
        }
    }

    /// Remove <TRACK> elements whose INTERLEAVE_INDEX is not in keepInterleaveIndices,
    /// then renumber the remaining tracks starting from 1
    private static func filterIxmlTracks(_ xml: inout String, keepInterleaveIndices: Set<Int>) {
        // Match each <TRACK>...</TRACK> block
        let trackPattern = "<TRACK>([\\s\\S]*?)</TRACK>"
        guard let regex = try? NSRegularExpression(pattern: trackPattern) else { return }

        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))

        // Parse each track's INTERLEAVE_INDEX and decide keep/remove
        struct TrackInfo {
            let range: Range<String.Index>
            let interleaveIndex: Int
            let content: String
        }

        var tracks: [TrackInfo] = []
        for match in matches {
            guard let swiftRange = Range(match.range, in: xml),
                  let contentRange = Range(match.range(at: 1), in: xml) else { continue }
            let content = String(xml[contentRange])

            // Extract INTERLEAVE_INDEX
            var idx = 0
            if let idxRegex = try? NSRegularExpression(pattern: "<INTERLEAVE_INDEX>\\s*(\\d+)\\s*</INTERLEAVE_INDEX>"),
               let idxMatch = idxRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let idxRange = Range(idxMatch.range(at: 1), in: content) {
                idx = Int(content[idxRange]) ?? 0
            }

            tracks.append(TrackInfo(range: swiftRange, interleaveIndex: idx, content: content))
        }

        guard !tracks.isEmpty else { return }

        // Build replacement: only kept tracks, with renumbered INTERLEAVE_INDEX
        let keptTracks = tracks.filter { keepInterleaveIndices.contains($0.interleaveIndex) }

        // Replace the entire TRACK_LIST content if it exists, otherwise replace tracks individually
        let trackListPattern = "<TRACK_LIST>([\\s\\S]*?)</TRACK_LIST>"
        if let tlRegex = try? NSRegularExpression(pattern: trackListPattern),
           let tlMatch = tlRegex.firstMatch(in: xml, range: NSRange(location: 0, length: nsString.length)),
           let tlRange = Range(tlMatch.range, in: xml) {

            var newTracks = ""
            for (newIdx, track) in keptTracks.enumerated() {
                var content = track.content
                // Update INTERLEAVE_INDEX and CHANNEL_INDEX to new 1-based index
                for tag in ["INTERLEAVE_INDEX", "CHANNEL_INDEX"] {
                    if let tagRegex = try? NSRegularExpression(pattern: "<\(tag)>[^<]*</\(tag)>"),
                       let tagMatch = tagRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                       let tagRange = Range(tagMatch.range, in: content) {
                        content.replaceSubrange(tagRange, with: "<\(tag)>\(newIdx + 1)</\(tag)>")
                    }
                }
                newTracks += "<TRACK>\(content)</TRACK>"
            }

            xml.replaceSubrange(tlRange, with: "<TRACK_LIST>\(newTracks)</TRACK_LIST>")
        }
    }

    // MARK: - Channel Merge

    static func mergeChannels(original: URL, output: URL, processedChannels: [Int: URL]) -> Bool {
        guard let originalFile = try? AVAudioFile(forReading: original) else { return false }

        let format = originalFile.processingFormat
        let channelCount = Int(format.channelCount)
        let frameCount = AVAudioFrameCount(originalFile.length)

        guard channelCount > 0, frameCount > 0 else { return false }

        // Read original into buffer
        guard let originalBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return false }
        originalFile.framePosition = 0
        do {
            try originalFile.read(into: originalBuffer)
        } catch { return false }

        // Read processed channel files
        var processedBuffers: [Int: AVAudioPCMBuffer] = [:]
        for (ch, url) in processedChannels {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                continue
            }
            file.framePosition = 0
            do {
                try file.read(into: buffer)
                processedBuffers[ch] = buffer
            } catch { continue }
        }

        // Create output format (interleaved for WAV writing)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard AVAudioFormat(settings: outputSettings) != nil else { return false }
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return false }
        outputBuffer.frameLength = frameCount

        guard let origData = originalBuffer.floatChannelData,
              let outData = outputBuffer.floatChannelData else { return false }

        // Copy channels: use processed if available, else original
        for ch in 0..<channelCount {
            if let processedBuf = processedBuffers[ch],
               let processedData = processedBuf.floatChannelData {
                let count = min(Int(frameCount), Int(processedBuf.frameLength))
                for i in 0..<count {
                    outData[ch][i] = processedData[0][i] // mono processed → channel
                }
                // Fill remaining with silence
                for i in count..<Int(frameCount) {
                    outData[ch][i] = 0
                }
            } else {
                // Copy from original
                for i in 0..<Int(frameCount) {
                    outData[ch][i] = origData[ch][i]
                }
            }
        }

        // Write output
        do {
            let outputFile = try AVAudioFile(forWriting: output, settings: outputSettings)
            try outputFile.write(from: outputBuffer)
        } catch { return false }

        // Downgrade from WaveFormatExtensible to simple PCM
        downgradeToSimplePcm(file: output)

        // Copy metadata chunks from original
        if let ixmlData = readIxmlChunk(from: original) {
            _ = writeChunk(to: output, chunkId: "iXML", data: ixmlData)
        }
        if let bextData = readChunk(from: original, chunkId: "bext") {
            _ = writeChunk(to: output, chunkId: "bext", data: bextData)
        }
        _ = removeChunk(from: output, chunkId: "LIST")

        return true
    }

    // MARK: - Helpers

    private static func writeChunkHeader(to handle: FileHandle, id: String, size: UInt32) {
        handle.write(id.data(using: .ascii)!)
        var sizeLE = size.littleEndian
        handle.write(Data(bytes: &sizeLE, count: 4))
    }
}

// MARK: - iXML Track Name Parser

private class IXMLTrackParser: NSObject, XMLParserDelegate {
    var trackNames: [String] = []
    private var currentElement = ""
    private var currentInterleaveIndex = 0
    private var currentTrackName = ""
    private var inTrack = false
    private var charBuffer = ""

    init(xml: String) {
        super.init()
        guard let data = xml.data(using: .utf8) else { return }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        currentElement = element
        charBuffer = ""
        if element == "TRACK" {
            inTrack = true
            currentInterleaveIndex = 0
            currentTrackName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        charBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if inTrack {
            if element == "INTERLEAVE_INDEX" {
                currentInterleaveIndex = Int(charBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            } else if element == "NAME" {
                currentTrackName = charBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if element == "TRACK" {
                inTrack = false
                // Ensure array is large enough (index is 1-based physical position)
                while trackNames.count <= currentInterleaveIndex {
                    trackNames.append("")
                }
                trackNames[currentInterleaveIndex] = currentTrackName
            }
        }
        charBuffer = ""
    }
}
