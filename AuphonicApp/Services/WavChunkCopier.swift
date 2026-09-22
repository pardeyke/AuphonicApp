import Foundation
import AVFoundation

nonisolated enum WavChunkCopier {

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

        while offset + 8 <= fileSize {
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

                // Update RIFF size: compare the padded sizes, since an odd
                // chunk carries a pad byte that counts towards the RIFF size
                let oldPadded = Int64(oldChunkTotalSize)
                let newPadded = Int64(8 + chunkData.count + (chunkData.count % 2 != 0 ? 1 : 0))
                riffSize = UInt32(Int64(riffSize) + newPadded - oldPadded)
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

    // MARK: - WAV Format Info

    /// Resolved sample format of a WAV file (WaveFormatExtensible is resolved to its subformat)
    struct WavFormatInfo {
        let formatTag: UInt16       // 1 = PCM integer, 3 = IEEE float
        let channels: Int
        let sampleRate: Double
        let bitsPerSample: Int
        let blockAlign: Int
        var isFloat: Bool { formatTag == 3 }
    }

    /// True if the file uses the RF64/BW64 container (64-bit sizes), which this parser does not support
    static func isRF64(file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { handle.closeFile() }
        guard let header = try? handle.read(upToCount: 4), header.count == 4,
              let id = String(data: header, encoding: .ascii) else { return false }
        return id == "RF64" || id == "BW64"
    }

    static func readFormatInfo(from file: URL) -> WavFormatInfo? {
        guard let fmtData = readChunk(from: file, chunkId: "fmt "),
              fmtData.count >= 16 else { return nil }

        var formatTag = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        let channels = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) }
        let sampleRate = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let blockAlign = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt16.self) }
        let bitsPerSample = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 14, as: UInt16.self) }

        // WaveFormatExtensible: real format is in the SubFormat GUID (first 2 bytes at offset 24)
        if formatTag == 0xFFFE, fmtData.count >= 26 {
            formatTag = fmtData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt16.self) }
        }

        return WavFormatInfo(
            formatTag: formatTag,
            channels: Int(channels),
            sampleRate: Double(sampleRate),
            bitsPerSample: Int(bitsPerSample),
            blockAlign: Int(blockAlign)
        )
    }

    /// Locate a chunk's payload in the file. Returns the byte offset of the chunk data
    /// (after the 8-byte chunk header) and its size.
    static func findChunkRange(in file: URL, chunkId: String) -> (offset: UInt64, size: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 12),
              headerData.count == 12,
              String(data: headerData[0..<4], encoding: .ascii) == "RIFF" else { return nil }

        var offset: UInt64 = 12
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0

        while offset + 8 <= fileSize {
            handle.seek(toFileOffset: offset)
            guard let chunkHeader = try? handle.read(upToCount: 8),
                  chunkHeader.count == 8 else { break }

            let id = String(data: chunkHeader[0..<4], encoding: .ascii) ?? ""
            let size = chunkHeader.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }

            if id == chunkId {
                return (offset: offset + 8, size: UInt64(size))
            }

            offset += 8 + UInt64(size)
            if size % 2 != 0 { offset += 1 } // padding
        }
        return nil
    }

    // MARK: - BWF Timecode

    /// Read the BWF TimeReference (samples since midnight) from the bext chunk.
    /// Layout: Description(256) + Originator(32) + OriginatorReference(32) +
    /// OriginationDate(10) + OriginationTime(8) = offset 338 (Low), 342 (High).
    static func readBextTimeReference(from file: URL) -> UInt64? {
        guard let bext = readChunk(from: file, chunkId: "bext"),
              bext.count >= 346 else { return nil }
        let low = bext.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 338, as: UInt32.self) }
        let high = bext.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 342, as: UInt32.self) }
        return (UInt64(high) << 32) | UInt64(low)
    }

    /// Read the timecode frame rate (fps) from the iXML SPEED section,
    /// e.g. <TIMECODE_RATE>25/1</TIMECODE_RATE> → 25.0
    static func readIxmlTimecodeRate(from file: URL) -> Double? {
        guard let ixmlData = readIxmlChunk(from: file),
              let xml = String(data: ixmlData, encoding: .utf8),
              let match = xml.range(of: "<TIMECODE_RATE>[^<]*</TIMECODE_RATE>", options: .regularExpression) else {
            return nil
        }

        let value = String(xml[match])
            .replacingOccurrences(of: "<TIMECODE_RATE>", with: "")
            .replacingOccurrences(of: "</TIMECODE_RATE>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = value.split(separator: "/")
        if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
            return num / den
        }
        return Double(value)
    }

    // MARK: - Helpers

    private static func writeChunkHeader(to handle: FileHandle, id: String, size: UInt32) {
        handle.write(id.data(using: .ascii)!)
        var sizeLE = size.littleEndian
        handle.write(Data(bytes: &sizeLE, count: 4))
    }
}

// MARK: - iXML Track Name Parser

nonisolated private final class IXMLTrackParser: NSObject, XMLParserDelegate {
    /// Highest interleave index accepted. WAV carries at most 65535 channels
    /// and real recorders a handful; a malformed index like 2000000000 used
    /// to allocate that many strings just by adding the file.
    static let maxInterleaveIndex = 256

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
                // Index is the 1-based physical position; ignore nonsense values
                if (1...Self.maxInterleaveIndex).contains(currentInterleaveIndex) {
                    while trackNames.count <= currentInterleaveIndex {
                        trackNames.append("")
                    }
                    trackNames[currentInterleaveIndex] = currentTrackName
                }
            }
        }
        charBuffer = ""
    }
}
