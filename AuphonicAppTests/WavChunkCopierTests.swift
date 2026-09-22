import Testing
import Foundation
import AVFoundation
@testable import AuphonicApp

struct WavChunkCopierTests {

    // MARK: - Test Helpers

    /// Create a minimal valid WAV file with optional extra chunks
    private func createTestWavFile(
        channels: UInt16 = 1,
        sampleRate: UInt32 = 48000,
        bitsPerSample: UInt16 = 24,
        frameCount: Int = 480,
        extraChunks: [(id: String, data: Data)] = []
    ) -> URL {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).wav")

        var fileData = Data()

        // RIFF header (placeholder size)
        fileData.append("RIFF".data(using: .ascii)!)
        fileData.append(Data(count: 4)) // placeholder
        fileData.append("WAVE".data(using: .ascii)!)

        // fmt chunk (16 bytes)
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)

        fileData.append("fmt ".data(using: .ascii)!)
        appendUInt32(&fileData, 16) // chunk size
        appendUInt16(&fileData, 1)  // PCM
        appendUInt16(&fileData, channels)
        appendUInt32(&fileData, sampleRate)
        appendUInt32(&fileData, byteRate)
        appendUInt16(&fileData, blockAlign)
        appendUInt16(&fileData, bitsPerSample)

        // Extra chunks (before data)
        for chunk in extraChunks {
            fileData.append(chunk.id.padding(toLength: 4, withPad: " ", startingAt: 0).data(using: .ascii)!)
            appendUInt32(&fileData, UInt32(chunk.data.count))
            fileData.append(chunk.data)
            if chunk.data.count % 2 != 0 {
                fileData.append(Data([0])) // pad byte
            }
        }

        // data chunk
        let dataSize = frameCount * Int(blockAlign)
        fileData.append("data".data(using: .ascii)!)
        appendUInt32(&fileData, UInt32(dataSize))
        fileData.append(Data(repeating: 0, count: dataSize))

        // Fix RIFF size
        let riffSize = UInt32(fileData.count - 8)
        fileData.replaceSubrange(4..<8, with: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })

        try! fileData.write(to: tempFile)
        return tempFile
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    // MARK: - readChunk

    @Test func readFmtChunk() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let fmtData = WavChunkCopier.readChunk(from: file, chunkId: "fmt ")
        #expect(fmtData != nil)
        #expect(fmtData?.count == 16)
    }

    @Test func readNonExistentChunk() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let data = WavChunkCopier.readChunk(from: file, chunkId: "bext")
        #expect(data == nil)
    }

    @Test func readChunkFromNonExistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).wav")
        let data = WavChunkCopier.readChunk(from: url, chunkId: "fmt ")
        #expect(data == nil)
    }

    @Test func readExtraChunk() {
        let bextData = Data("bext test data here!!".utf8)
        let file = createTestWavFile(extraChunks: [("bext", bextData)])
        defer { try? FileManager.default.removeItem(at: file) }

        let read = WavChunkCopier.readChunk(from: file, chunkId: "bext")
        #expect(read == bextData)
    }

    // MARK: - writeChunk (append)

    @Test func writeNewChunk() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let testData = Data("hello iXML world".utf8)
        let success = WavChunkCopier.writeChunk(to: file, chunkId: "iXML", data: testData)
        #expect(success)

        // Verify it can be read back
        let readBack = WavChunkCopier.readChunk(from: file, chunkId: "iXML")
        #expect(readBack == testData)
    }

    // MARK: - writeChunk (replace)

    @Test func replaceExistingChunk() {
        let originalData = Data("original bext".utf8)
        let file = createTestWavFile(extraChunks: [("bext", originalData)])
        defer { try? FileManager.default.removeItem(at: file) }

        let newData = Data("replaced bext data here!".utf8)
        let success = WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: newData)
        #expect(success)

        let readBack = WavChunkCopier.readChunk(from: file, chunkId: "bext")
        #expect(readBack == newData)

        // Verify other chunks still intact
        let fmtData = WavChunkCopier.readChunk(from: file, chunkId: "fmt ")
        #expect(fmtData != nil)
    }

    // MARK: - removeChunk

    @Test func removeExistingChunk() {
        let bextData = Data("to be removed".utf8)
        let file = createTestWavFile(extraChunks: [("bext", bextData)])
        defer { try? FileManager.default.removeItem(at: file) }

        let success = WavChunkCopier.removeChunk(from: file, chunkId: "bext")
        #expect(success)

        let readBack = WavChunkCopier.readChunk(from: file, chunkId: "bext")
        #expect(readBack == nil)

        // fmt should still be readable
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "fmt ") != nil)
    }

    @Test func removeNonExistentChunkSucceeds() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let success = WavChunkCopier.removeChunk(from: file, chunkId: "LIST")
        #expect(success) // Not found is not an error
    }

    // MARK: - readIxmlTrackNames

    @Test func readIxmlTrackNames() {
        let ixml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML>
            <TRACK_LIST>
                <TRACK>
                    <INTERLEAVE_INDEX>1</INTERLEAVE_INDEX>
                    <NAME>Boom</NAME>
                </TRACK>
                <TRACK>
                    <INTERLEAVE_INDEX>2</INTERLEAVE_INDEX>
                    <NAME>Lav1</NAME>
                </TRACK>
                <TRACK>
                    <INTERLEAVE_INDEX>3</INTERLEAVE_INDEX>
                    <NAME>Lav2</NAME>
                </TRACK>
            </TRACK_LIST>
        </BWFXML>
        """
        let ixmlData = Data(ixml.utf8)
        let file = createTestWavFile(channels: 3, extraChunks: [("iXML", ixmlData)])
        defer { try? FileManager.default.removeItem(at: file) }

        let names = WavChunkCopier.readIxmlTrackNames(from: file)
        #expect(names.count >= 4) // index 0 is empty, 1=Boom, 2=Lav1, 3=Lav2
        #expect(names[1] == "Boom")
        #expect(names[2] == "Lav1")
        #expect(names[3] == "Lav2")
    }

    /// A malformed interleave index used to allocate that many strings
    @Test func readIxmlTrackNamesIgnoresAbsurdIndices() {
        let ixml = """
        <BWFXML><TRACK_LIST>
            <TRACK><INTERLEAVE_INDEX>2000000000</INTERLEAVE_INDEX><NAME>Bogus</NAME></TRACK>
            <TRACK><INTERLEAVE_INDEX>-1</INTERLEAVE_INDEX><NAME>Negative</NAME></TRACK>
            <TRACK><INTERLEAVE_INDEX>0</INTERLEAVE_INDEX><NAME>Zero</NAME></TRACK>
            <TRACK><INTERLEAVE_INDEX>2</INTERLEAVE_INDEX><NAME>Lav</NAME></TRACK>
        </TRACK_LIST></BWFXML>
        """
        let file = createTestWavFile(channels: 2, extraChunks: [("iXML", Data(ixml.utf8))])
        defer { try? FileManager.default.removeItem(at: file) }

        let names = WavChunkCopier.readIxmlTrackNames(from: file)
        #expect(names.count == 3)
        #expect(names[2] == "Lav")
        #expect(!names.contains("Bogus"))
        #expect(!names.contains("Negative"))
        #expect(!names.contains("Zero"))
    }

    @Test func readChunkOnTruncatedHeaderReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("short_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("RIFF\u{0}\u{0}\u{0}\u{0}WAVE".utf8).write(to: url)     // exactly 12 bytes
        #expect(WavChunkCopier.readChunk(from: url, chunkId: "fmt ") == nil)

        try Data("RIFF".utf8).write(to: url)                                 // shorter than a header
        #expect(WavChunkCopier.readChunk(from: url, chunkId: "fmt ") == nil)
    }

    @Test func readIxmlTrackNamesNoIxml() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let names = WavChunkCopier.readIxmlTrackNames(from: file)
        #expect(names.isEmpty)
    }

    // MARK: - Multiple Chunk Operations

    @Test func writeAndRemoveMultipleChunks() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let ixmlData = Data("<BWFXML/>".utf8)
        let bextData = Data("bext content".utf8)
        let listData = Data("LIST content".utf8)

        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "iXML", data: ixmlData))
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: bextData))
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "LIST", data: listData))

        // All readable
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "iXML") == ixmlData)
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "bext") == bextData)
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "LIST") == listData)

        // Remove LIST
        #expect(WavChunkCopier.removeChunk(from: file, chunkId: "LIST"))
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "LIST") == nil)

        // Others still readable
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "iXML") == ixmlData)
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "bext") == bextData)
    }

    /// The RIFF size field must always equal the file size minus 8, also when
    /// a replacement changes the chunk's padding parity (odd → even and back).
    private func riffSizeMatchesFile(_ file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file), data.count >= 8 else { return false }
        let riffSize = data[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return Int(UInt32(littleEndian: riffSize)) == data.count - 8
    }

    @Test func riffSizeStaysConsistentAcrossParityChanges() {
        let file = createTestWavFile(extraChunks: [("bext", Data("odd size chunk".utf8))])  // 14 bytes
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(riffSizeMatchesFile(file))

        // even → odd (used to leave the RIFF size one byte short)
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: Data("thirteen chars".utf8).dropLast()))
        #expect(riffSizeMatchesFile(file))

        // odd → even (used to leave it one byte too large)
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: Data("replaced bext data here!".utf8)))
        #expect(riffSizeMatchesFile(file))

        // odd → odd
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: Data("a".utf8)))
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "bext", data: Data("abc".utf8)))
        #expect(riffSizeMatchesFile(file))

        // append and remove keep it consistent too
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "iXML", data: Data("xyz".utf8)))
        #expect(riffSizeMatchesFile(file))
        #expect(WavChunkCopier.removeChunk(from: file, chunkId: "bext"))
        #expect(riffSizeMatchesFile(file))

        #expect(WavChunkCopier.readChunk(from: file, chunkId: "iXML") == Data("xyz".utf8))
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "fmt ") != nil)
    }

    @Test func writeOddSizedChunk() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        // Odd-length data requires padding
        let oddData = Data("odd".utf8) // 3 bytes
        #expect(WavChunkCopier.writeChunk(to: file, chunkId: "iXML", data: oddData))

        let readBack = WavChunkCopier.readChunk(from: file, chunkId: "iXML")
        #expect(readBack == oddData)

        // File should still be valid (fmt readable)
        #expect(WavChunkCopier.readChunk(from: file, chunkId: "fmt ") != nil)
    }
}
