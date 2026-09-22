import Foundation

/// Session cache of rendered waveforms (per channel plus the combined lane).
///
/// Keyed by path *and* the file's size and modification date: the batch
/// reuses output paths, so a URL alone would show the previous run's waveform
/// for a freshly written file. Bounded, least recently used first out —
/// every entry holds (channels + 1) × resolution floats.
final class WaveformCache {
    struct Key: Hashable {
        let path: String
        let size: UInt64
        let modified: Date
    }

    let limit: Int
    private var entries: [Key: [Int: [Float]]] = [:]
    private var recency: [Key] = []       // oldest first

    init(limit: Int = 32) {
        self.limit = limit
    }

    var count: Int { entries.count }

    /// `nil` when the file cannot be stat'ed, which also means "never cache"
    static func key(for url: URL) -> Key? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Key(path: url.path, size: size, modified: modified)
    }

    func waveforms(for url: URL) -> [Int: [Float]]? {
        guard let key = Self.key(for: url), let hit = entries[key] else { return nil }
        touch(key)
        return hit
    }

    func store(_ waveforms: [Int: [Float]], for url: URL) {
        guard let key = Self.key(for: url) else { return }
        entries[key] = waveforms
        touch(key)
        while entries.count > limit, let oldest = recency.first {
            recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
