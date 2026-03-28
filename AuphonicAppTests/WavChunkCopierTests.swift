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

    // MARK: - readWavBitDepth

    @Test func readBitDepth24() {
        let file = createTestWavFile(bitsPerSample: 24)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(WavChunkCopier.readWavBitDepth(from: file) == 24)
    }

    @Test func readBitDepth16() {
        let file = createTestWavFile(bitsPerSample: 16)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(WavChunkCopier.readWavBitDepth(from: file) == 16)
    }

    @Test func readBitDepthNonWav() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).wav")
        #expect(WavChunkCopier.readWavBitDepth(from: url) == 0)
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

    @Test func readIxmlTrackNamesNoIxml() {
        let file = createTestWavFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let names = WavChunkCopier.readIxmlTrackNames(from: file)
        #expect(names.isEmpty)
    }

    // MARK: - updateIxmlForOutput

    @Test func updateIxmlBitDepth() {
        let ixml = "<BWFXML><AUDIO_BIT_DEPTH>24</AUDIO_BIT_DEPTH></BWFXML>"
        let data = Data(ixml.utf8)
        let updated = WavChunkCopier.updateIxmlForOutput(ixmlData: data, outputBitDepth: 16, extractedChannel: 0)
        let str = String(data: updated, encoding: .utf8)!
        #expect(str.contains("<AUDIO_BIT_DEPTH>16</AUDIO_BIT_DEPTH>"))
    }

    @Test func updateIxmlSingleChannelExtraction() {
        let ixml = """
        <BWFXML>
            <CHANNEL_COUNT>4</CHANNEL_COUNT>
            <TRACK_COUNT>4</TRACK_COUNT>
            <TRACK_LIST>
                <TRACK><INTERLEAVE_INDEX>1</INTERLEAVE_INDEX><NAME>Boom</NAME></TRACK>
                <TRACK><INTERLEAVE_INDEX>2</INTERLEAVE_INDEX><NAME>Lav1</NAME></TRACK>
                <TRACK><INTERLEAVE_INDEX>3</INTERLEAVE_INDEX><NAME>Lav2</NAME></TRACK>
                <TRACK><INTERLEAVE_INDEX>4</INTERLEAVE_INDEX><NAME>Mix</NAME></TRACK>
            </TRACK_LIST>
        </BWFXML>
        """
        let data = Data(ixml.utf8)
        let updated = WavChunkCopier.updateIxmlForOutput(ixmlData: data, outputBitDepth: 24, extractedChannel: 2)
        let str = String(data: updated, encoding: .utf8)!
        #expect(str.contains("<CHANNEL_COUNT>1</CHANNEL_COUNT>"))
        #expect(str.contains("<TRACK_COUNT>1</TRACK_COUNT>"))
    }

    @Test func updateIxmlLRExtraction() {
        let ixml = """
        <BWFXML>
            <CHANNEL_COUNT>4</CHANNEL_COUNT>
            <TRACK_COUNT>4</TRACK_COUNT>
        </BWFXML>
        """
        let data = Data(ixml.utf8)
        let updated = WavChunkCopier.updateIxmlForOutput(ixmlData: data, outputBitDepth: 24, extractedChannel: -1)
        let str = String(data: updated, encoding: .utf8)!
        #expect(str.contains("<CHANNEL_COUNT>2</CHANNEL_COUNT>"))
        #expect(str.contains("<TRACK_COUNT>2</TRACK_COUNT>"))
    }

    @Test func updateIxmlNoExtraction() {
        let ixml = "<BWFXML><CHANNEL_COUNT>2</CHANNEL_COUNT></BWFXML>"
        let data = Data(ixml.utf8)
        let updated = WavChunkCopier.updateIxmlForOutput(ixmlData: data, outputBitDepth: 24, extractedChannel: 0)
        let str = String(data: updated, encoding: .utf8)!
        // Channel count should not change
        #expect(str.contains("<CHANNEL_COUNT>2</CHANNEL_COUNT>"))
    }

    // MARK: - downgradeToSimplePcm

    @Test func downgradeAlreadyPcmIsNoop() {
        // Create WAV with 18-byte PCM fmt chunk (tag=0x0001, with cbSize=0)
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_pcm18_\(UUID().uuidString).wav")
        var fileData = Data()
        let channels: UInt16 = 1
        let sampleRate: UInt32 = 48000
        let bitsPerSample: UInt16 = 24
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize: UInt32 = 480 * UInt32(blockAlign)

        // RIFF header
        fileData.append("RIFF".data(using: .ascii)!)
        fileData.append(Data(count: 4)) // placeholder
        fileData.append("WAVE".data(using: .ascii)!)
        // fmt chunk (18 bytes: 16 PCM + 2 cbSize)
        fileData.append("fmt ".data(using: .ascii)!)
        appendUInt32(&fileData, 18) // chunk size = 18
        appendUInt16(&fileData, 1)  // PCM tag
        appendUInt16(&fileData, channels)
        appendUInt32(&fileData, sampleRate)
        appendUInt32(&fileData, byteRate)
        appendUInt16(&fileData, blockAlign)
        appendUInt16(&fileData, bitsPerSample)
        appendUInt16(&fileData, 0)  // cbSize = 0
        // data chunk
        fileData.append("data".data(using: .ascii)!)
        appendUInt32(&fileData, dataSize)
        fileData.append(Data(repeating: 0, count: Int(dataSize)))
        // Fix RIFF size
        let riffSize = UInt32(fileData.count - 8)
        fileData.replaceSubrange(4..<8, with: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        try! fileData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let sizeBefore = try! FileManager.default.attributesOfItem(atPath: tempFile.path)[.size] as! UInt64

        let result = WavChunkCopier.downgradeToSimplePcm(file: tempFile)
        #expect(result == true) // Returns true for already-PCM

        let sizeAfter = try! FileManager.default.attributesOfItem(atPath: tempFile.path)[.size] as! UInt64
        #expect(sizeBefore == sizeAfter) // File unchanged
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
