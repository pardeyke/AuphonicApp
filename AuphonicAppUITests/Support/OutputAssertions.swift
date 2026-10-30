import XCTest

/// What the simulated Auphonic does to audio (`SimulatedAuphonicAPI.processingGain`)
let simulatedGain = 0.5

/// How one channel of an output file must relate to the original
enum ChannelExpectation {
    /// Bit-identical to the original's channel
    case untouched
    /// The original channel times the simulated gain, after a round trip
    /// through a `bits`-deep integer WAV (24 for singletrack, 16 for multitrack tracks)
    case processed(bits: Int)
    /// The simulated mono mixdown: the average of the given processed
    /// original channels (0-based), delivered at `bits`
    case mixdown(of: [Int], bits: Int)
}

/// Verifies a Mix Preparation output against its original: identical chunk
/// layout and metadata, identical sample format and length, untouched
/// channels bit-perfect, processed channels carrying the simulated result.
func assertMixPrepOutput(
    original originalURL: URL,
    output outputURL: URL,
    channels expectations: [ChannelExpectation],
    file: StaticString = #filePath, line: UInt = #line
) throws {
    let original = try WavFile(url: originalURL)
    let output = try WavFile(url: outputURL)

    XCTAssertEqual(output.chunkIDs, original.chunkIDs, "chunk layout changed", file: file, line: line)
    for chunk in original.chunks where chunk.id != "data" {
        XCTAssertEqual(output.payload(chunk.id), original.payload(chunk.id),
                       "'\(chunk.id)' chunk is not bit-identical", file: file, line: line)
    }
    XCTAssertEqual(output.channels, original.channels, file: file, line: line)
    XCTAssertEqual(output.bitsPerSample, original.bitsPerSample, file: file, line: line)
    XCTAssertEqual(output.isFloat, original.isFloat, file: file, line: line)
    XCTAssertEqual(output.frameCount, original.frameCount, "length changed", file: file, line: line)
    XCTAssertEqual(expectations.count, original.channels, "one expectation per channel", file: file, line: line)

    for (channel, expectation) in expectations.enumerated() {
        switch expectation {
        case .untouched:
            XCTAssertTrue(output.rawChannel(channel) == original.rawChannel(channel),
                          "channel \(channel + 1) should be bit-identical", file: file, line: line)

        case .processed(let bits):
            let error = maxError(
                output.samples(channel: channel),
                original.samples(channel: channel).map { $0 * simulatedGain })
            XCTAssertLessThanOrEqual(error, tolerance(bits: bits, container: original),
                                     "channel \(channel + 1) is not the processed original (max error \(error))",
                                     file: file, line: line)

        case .mixdown(let sources, let bits):
            let originals = sources.map { original.samples(channel: $0) }
            var expected = [Double](repeating: 0, count: original.frameCount)
            for source in originals {
                for i in expected.indices {
                    // Each track comes through the simulation as Float
                    expected[i] += Double(Float(source[i]) * Float(simulatedGain)) / Double(sources.count)
                }
            }
            let error = maxError(output.samples(channel: channel), expected)
            XCTAssertLessThanOrEqual(error, tolerance(bits: bits, container: original) + 1e-6,
                                     "channel \(channel + 1) is not the mixdown (max error \(error))",
                                     file: file, line: line)
        }
    }
}

/// Quantization of the delivered format plus the container's own
private func tolerance(bits: Int, container: WavFile) -> Double {
    let delivered = 1 / pow(2, Double(bits - 1))
    let stored = container.isFloat ? 0 : 1 / pow(2, Double(container.bitsPerSample - 1))
    return delivered + stored + 1e-7
}

private func maxError(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return .infinity }
    var worst = 0.0
    for i in a.indices {
        let difference = abs(a[i] - b[i])
        if difference > worst { worst = difference }
    }
    return worst
}

// MARK: - API log

extension Dictionary where Key == String, Value == Any {
    subscript(path path: String) -> Any? {
        var current: Any? = self
        for key in path.split(separator: ".") {
            current = (current as? [String: Any])?[String(key)]
        }
        return current
    }

    var settings: [String: Any] { self["settings"] as? [String: Any] ?? [:] }
    var algorithms: [String: Any] { settings["algorithms"] as? [String: Any] ?? [:] }
    var outputFormat: String? { (settings["output_files"] as? [[String: Any]])?.first?["format"] as? String }
    var uploadedFiles: [[String: Any]] { self["files"] as? [[String: Any]] ?? [] }
    var title: String { self["title"] as? String ?? "" }
}
