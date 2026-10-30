import Foundation

/// Reads a WAV file the way the tests need to compare it: the list of chunks
/// in file order, the format, and the samples of each channel as doubles in
/// -1…1. Independent of the app's own RIFF code, so a bug there cannot hide
/// itself in the verification.
struct WavFile {
    struct Chunk {
        let id: String
        let offset: Int     // of the payload
        let size: Int
    }

    let data: Data
    let chunks: [Chunk]
    let formatTag: Int
    let channels: Int
    let sampleRate: Int
    let bitsPerSample: Int

    var isFloat: Bool { formatTag == 3 || (formatTag == 0xFFFE && extensibleSubFormat == 3) }
    private let extensibleSubFormat: Int

    var bytesPerFrame: Int { channels * bitsPerSample / 8 }
    var frameCount: Int { (chunk("data")?.size ?? 0) / max(bytesPerFrame, 1) }

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
            throw NSError(domain: "WavFile", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a RIFF/WAVE file"])
        }
        self.data = data

        var chunks: [Chunk] = []
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data.readLE(UInt32.self, at: offset + 4))
            chunks.append(Chunk(id: id, offset: offset + 8, size: size))
            offset += 8 + size + (size % 2)
        }
        self.chunks = chunks

        guard let fmt = chunks.first(where: { $0.id == "fmt " }) else {
            throw NSError(domain: "WavFile", code: 2, userInfo: [NSLocalizedDescriptionKey: "no fmt chunk"])
        }
        formatTag = Int(data.readLE(UInt16.self, at: fmt.offset))
        channels = Int(data.readLE(UInt16.self, at: fmt.offset + 2))
        sampleRate = Int(data.readLE(UInt32.self, at: fmt.offset + 4))
        bitsPerSample = Int(data.readLE(UInt16.self, at: fmt.offset + 14))
        extensibleSubFormat = fmt.size >= 26 ? Int(data.readLE(UInt16.self, at: fmt.offset + 24)) : 0
    }

    func chunk(_ id: String) -> Chunk? {
        chunks.first { $0.id == id }
    }

    func payload(_ id: String) -> Data? {
        chunk(id).map { data[$0.offset..<$0.offset + $0.size] }
    }

    var chunkIDs: [String] { chunks.map(\.id) }

    /// bext TimeReference
    var timeReference: UInt64? {
        guard let bext = chunk("bext"), bext.size >= 346 else { return nil }
        return data.readLE(UInt64.self, at: bext.offset + 338)
    }

    /// Raw bytes of one channel's samples (for bit-exact comparison)
    func rawChannel(_ channel: Int) -> Data {
        guard let audio = chunk("data") else { return Data() }
        let width = bitsPerSample / 8
        var out = Data(capacity: frameCount * width)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!.advanced(by: audio.offset + channel * width)
            for frame in 0..<frameCount {
                out.append(base.advanced(by: frame * bytesPerFrame).assumingMemoryBound(to: UInt8.self), count: width)
            }
        }
        return out
    }

    /// One channel as doubles in -1…1
    func samples(channel: Int, limit: Int? = nil) -> [Double] {
        guard let audio = chunk("data") else { return [] }
        let width = bitsPerSample / 8
        let count = min(frameCount, limit ?? .max)
        var out = [Double](repeating: 0, count: count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!.advanced(by: audio.offset + channel * width)
            for frame in 0..<count {
                let p = base.advanced(by: frame * bytesPerFrame)
                switch (isFloat, bitsPerSample) {
                case (true, 32):
                    out[frame] = Double(Float(bitPattern: p.loadUnaligned(as: UInt32.self)))
                case (_, 16):
                    out[frame] = Double(p.loadUnaligned(as: Int16.self)) / 32_768
                case (_, 24):
                    let b = p.assumingMemoryBound(to: UInt8.self)
                    var v = Int32(b[0]) | Int32(b[1]) << 8 | Int32(b[2]) << 16
                    if v & 0x80_0000 != 0 { v |= ~0xFF_FFFF }
                    out[frame] = Double(v) / 8_388_608
                case (_, 32):
                    out[frame] = Double(p.loadUnaligned(as: Int32.self)) / 2_147_483_648
                default:
                    out[frame] = .nan
                }
            }
        }
        return out
    }
}
