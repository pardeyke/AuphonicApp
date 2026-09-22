import Foundation
import Compression

enum ZipArchiveError: LocalizedError {
    case notAZipFile
    case zip64NotSupported
    case unsupportedCompression(UInt16)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notAZipFile:
            return "Downloaded file is not a ZIP archive"
        case .zip64NotSupported:
            return "ZIP64 archives (>4 GB) are not supported"
        case .unsupportedCompression(let method):
            return "Unsupported ZIP compression method \(method)"
        case .corrupt(let detail):
            return "Damaged ZIP archive: \(detail)"
        }
    }
}

/// Minimal read-only ZIP reader for Auphonic's individual-tracks archive.
/// Supports the two methods Auphonic uses — stored (0) and deflate (8) —
/// without external dependencies, so it works inside the app sandbox.
nonisolated enum ZipArchive {

    struct Entry {
        let name: String
        let uncompressedSize: Int
        let compressionMethod: UInt16
        let localHeaderOffset: Int
    }

    /// Extract all file entries into `directory`, returning the written files
    /// in central-directory order.
    @discardableResult
    static func extract(_ archive: URL, to directory: URL) throws -> [URL] {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try readCentralDirectory(data)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        for entry in entries {
            // Skip directories and macOS resource-fork noise
            let fileName = (entry.name as NSString).lastPathComponent
            if entry.name.hasSuffix("/") || fileName.isEmpty || fileName.hasPrefix("._")
                || entry.name.hasPrefix("__MACOSX/") {
                continue
            }

            let payload = try payload(for: entry, in: data)
            let destination = directory.appendingPathComponent(fileName)
            try payload.write(to: destination)
            written.append(destination)
        }
        return written
    }

    // MARK: - Central Directory

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralFileHeaderSignature: UInt32 = 0x0201_4b50
    private static let localFileHeaderSignature: UInt32 = 0x0403_4b50

    static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipArchiveError.notAZipFile }

        // Find the End of Central Directory record (may be followed by a comment)
        let maxCommentLength = 0xFFFF
        let searchStart = max(0, data.count - 22 - maxCommentLength)
        var eocd: Int?
        var index = data.count - 22
        while index >= searchStart {
            if data.readUInt32(at: index) == endOfCentralDirectorySignature {
                eocd = index
                break
            }
            index -= 1
        }
        guard let eocdOffset = eocd else { throw ZipArchiveError.notAZipFile }

        let entryCount = Int(data.readUInt16(at: eocdOffset + 10))
        let directorySize = Int(data.readUInt32(at: eocdOffset + 12))
        let directoryOffset = Int(data.readUInt32(at: eocdOffset + 16))

        guard directoryOffset != 0xFFFF_FFFF, directorySize != 0xFFFF_FFFF else {
            throw ZipArchiveError.zip64NotSupported
        }
        guard directoryOffset + directorySize <= data.count else {
            throw ZipArchiveError.corrupt("central directory out of bounds")
        }

        var entries: [Entry] = []
        var cursor = directoryOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  data.readUInt32(at: cursor) == centralFileHeaderSignature else {
                throw ZipArchiveError.corrupt("bad central directory header")
            }

            let method = data.readUInt16(at: cursor + 10)
            let uncompressedSize = Int(data.readUInt32(at: cursor + 24))
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let localOffset = Int(data.readUInt32(at: cursor + 42))

            guard localOffset != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF else {
                throw ZipArchiveError.zip64NotSupported
            }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw ZipArchiveError.corrupt("truncated file name")
            }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            entries.append(Entry(
                name: name,
                uncompressedSize: uncompressedSize,
                compressionMethod: method,
                localHeaderOffset: localOffset
            ))

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    // MARK: - Entry Payload

    /// Read (and inflate if needed) one entry's bytes. Sizes come from the
    /// local header, which is authoritative for the stored bytes.
    private static func payload(for entry: Entry, in data: Data) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count,
              data.readUInt32(at: header) == localFileHeaderSignature else {
            throw ZipArchiveError.corrupt("bad local header for \(entry.name)")
        }

        let nameLength = Int(data.readUInt16(at: header + 26))
        let extraLength = Int(data.readUInt16(at: header + 28))
        var compressedSize = Int(data.readUInt32(at: header + 18))
        var uncompressedSize = Int(data.readUInt32(at: header + 22))

        // Streamed entries put the sizes in a trailing data descriptor;
        // fall back to the central directory values in that case.
        if compressedSize == 0 && uncompressedSize == 0 {
            uncompressedSize = entry.uncompressedSize
            compressedSize = data.count - (header + 30 + nameLength + extraLength)
        }
        if uncompressedSize == 0 { uncompressedSize = entry.uncompressedSize }

        let start = header + 30 + nameLength + extraLength
        guard start + compressedSize <= data.count else {
            throw ZipArchiveError.corrupt("truncated entry \(entry.name)")
        }
        let compressed = data[start..<(start + compressedSize)]

        switch entry.compressionMethod {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(Data(compressed), uncompressedSize: uncompressedSize)
        default:
            throw ZipArchiveError.unsupportedCompression(entry.compressionMethod)
        }
    }

    /// Raw DEFLATE decompression via libcompression
    private static func inflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        var output = Data(count: uncompressedSize)
        let decoded: Int = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dst, uncompressedSize,
                    src, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard decoded == uncompressedSize else {
            throw ZipArchiveError.corrupt("inflate produced \(decoded) of \(uncompressedSize) bytes")
        }
        return output
    }
}

// MARK: - Little-endian readers

nonisolated private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        guard base + 2 <= endIndex else { return 0 }
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        guard base + 4 <= endIndex else { return 0 }
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
