import Foundation

/// Builds broadcast WAV files byte by byte, the way field recorders write
/// them: `bext` (with the timecode in TimeReference), `iXML` (track names),
/// optional extra chunks, `fmt `, then `data`. Every channel carries its own
/// deterministic tone, so a test can tell channels apart after processing.
struct WavFixture {
    enum SampleFormat {
        case float32
        case int24
        case int16

        var bitsPerSample: Int {
            switch self {
            case .float32: return 32
            case .int24: return 24
            case .int16: return 16
            }
        }
    }

    var channels = 2
    var sampleRate = 48_000
    var format = SampleFormat.float32
    var seconds = 2.0
    /// bext TimeReference in samples since midnight; `nil` writes no bext chunk
    var timeReference: UInt64? = 0
    /// iXML track names; empty writes no iXML chunk
    var trackNames: [String] = []
    /// Chunks written between iXML and fmt, e.g. ("PAD ", 1024 zero bytes)
    var extraChunks: [(id: String, data: Data)] = []

    var frames: Int { Int(seconds * Double(sampleRate)) }

    /// Timecode helper: hours/minutes/seconds since midnight as samples
    static func timeReference(h: Int, m: Int, s: Int, sampleRate: Int = 48_000) -> UInt64 {
        UInt64((h * 3600 + m * 60 + s) * sampleRate)
    }

    /// The test signal: a different frequency and level per channel
    static func sample(channel: Int, frame: Int, sampleRate: Int) -> Double {
        let frequency = 110.0 * Double(channel + 1)
        let amplitude = 0.8 - 0.1 * Double(channel % 6)
        return amplitude * sin(2 * .pi * frequency * Double(frame) / Double(sampleRate))
    }

    @discardableResult
    func write(to url: URL) throws -> URL {
        var body = Data()

        if let timeReference {
            var bext = Data(count: 602)
            Self.put(Array("UITest fixture".utf8), into: &bext, at: 0)          // Description
            Self.put(Array("AuphonicAppUITests".utf8), into: &bext, at: 256)    // Originator
            bext.replaceSubrange(338..<346, with: withUnsafeBytes(of: timeReference.littleEndian) { Data($0) })
            Self.appendChunk("bext", bext, to: &body)
        }

        if !trackNames.isEmpty {
            Self.appendChunk("iXML", Data(Self.ixml(trackNames: trackNames).utf8), to: &body)
        }

        for chunk in extraChunks {
            Self.appendChunk(chunk.id, chunk.data, to: &body)
        }

        var fmt = Data()
        let bytesPerSample = format.bitsPerSample / 8
        fmt.appendLE(UInt16(format == .float32 ? 3 : 1))
        fmt.appendLE(UInt16(channels))
        fmt.appendLE(UInt32(sampleRate))
        fmt.appendLE(UInt32(sampleRate * channels * bytesPerSample))
        fmt.appendLE(UInt16(channels * bytesPerSample))
        fmt.appendLE(UInt16(format.bitsPerSample))
        Self.appendChunk("fmt ", fmt, to: &body)

        var audio = Data(capacity: frames * channels * bytesPerSample)
        for frame in 0..<frames {
            for channel in 0..<channels {
                let value = Self.sample(channel: channel, frame: frame, sampleRate: sampleRate)
                switch format {
                case .float32:
                    audio.appendLE(Float(value).bitPattern)
                case .int24:
                    let scaled = Int32((value * 8_388_607).rounded())
                    let bytes = withUnsafeBytes(of: scaled.littleEndian) { Array($0) }
                    audio.append(contentsOf: bytes[0..<3])
                case .int16:
                    audio.appendLE(Int16((value * 32_767).rounded()))
                }
            }
        }
        Self.appendChunk("data", audio, to: &body)

        var file = Data("RIFF".utf8)
        file.appendLE(UInt32(4 + body.count))
        file.append(Data("WAVE".utf8))
        file.append(body)
        try file.write(to: url)
        return url
    }

    private static func appendChunk(_ id: String, _ data: Data, to body: inout Data) {
        body.append(Data(id.utf8))
        body.appendLE(UInt32(data.count))
        body.append(data)
        if data.count % 2 == 1 { body.append(0) }
    }

    private static func put(_ bytes: [UInt8], into data: inout Data, at offset: Int) {
        data.replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }

    private static func ixml(trackNames: [String]) -> String {
        let tracks = trackNames.enumerated().map { index, name in
            """
            <TRACK><CHANNEL_INDEX>\(index + 1)</CHANNEL_INDEX><INTERLEAVE_INDEX>\(index + 1)</INTERLEAVE_INDEX><NAME>\(name)</NAME></TRACK>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML><IXML_VERSION>2.10</IXML_VERSION><SPEED><TIMECODE_RATE>25/1</TIMECODE_RATE></SPEED>\
        <TRACK_LIST><TRACK_COUNT>\(trackNames.count)</TRACK_COUNT>\(tracks)</TRACK_LIST></BWFXML>
        """
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        Swift.withUnsafeMutableBytes(of: &value) { raw in
            copyBytes(to: raw.bindMemory(to: UInt8.self), from: (startIndex + offset)..<(startIndex + offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}
