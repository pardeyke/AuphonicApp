import Testing
import Foundation
@testable import AuphonicApp

// MARK: - Production Mode & Job Counts

struct ProductionModeTests {

    private func makeConfig(channels: Int) -> ChannelConfig {
        let config = ChannelConfig()
        config.configure(count: channels, trackNames: ["BOOM", "LAVMIX", "LAV1", "LAV2"])
        return config
    }

    @Test func singletrackBillsOneProductionPerChannel() {
        let config = makeConfig(channels: 4)
        config.productionMode = .singletrack
        #expect(config.apiCallCount == 4)
    }

    @Test func multitrackBillsOneProductionPerFile() {
        let config = makeConfig(channels: 4)
        config.productionMode = .multitrack
        #expect(config.apiCallCount == 1)

        config.channels[0].enabled = false
        #expect(config.apiCallCount == 1)

        config.deselectAll()
        #expect(config.apiCallCount == 0)
    }

    @Test func multitrackIsValidWithoutPerTrackAlgorithms() {
        let config = makeConfig(channels: 3)
        config.productionMode = .singletrack
        #expect(!config.hasValidJobConfiguration)   // nothing enabled yet

        config.productionMode = .multitrack
        #expect(config.hasValidJobConfiguration)    // master leveler/gates still process
    }

    @Test func trackIdsAreDerivedFromChannelNames() {
        let config = makeConfig(channels: 4)
        let ids = config.enabledChannels.map { config.trackId(for: $0) }
        #expect(ids == ["Ch_1_BOOM", "Ch_2_LAVMIX", "Ch_3_LAV1", "Ch_4_LAV2"])
        #expect(Set(ids).count == ids.count)        // unique
    }

    // MARK: Output files

    @Test func multitrackAlwaysRequestsIndividualTracks() {
        let config = makeConfig(channels: 2)
        let files = config.multitrackOutputFiles(bitDepth: 24)
        #expect(files.count == 1)
        #expect(files[0]["format"] as? String == "tracks")
        #expect(files[0]["ending"] as? String == "wav.zip")
    }

    @Test func mixdownIsRequestedAsMonoWhenEnabled() {
        let config = makeConfig(channels: 2)
        config.downloadMixdown = true

        let files = config.multitrackOutputFiles(bitDepth: 32)
        #expect(files.count == 2)

        let mixdown = files[1]
        #expect(mixdown["format"] as? String == "wav-24bit")
        #expect(mixdown["mono_mixdown"] as? Bool == true)
    }

    // MARK: Per-track algorithms

    @Test func perTrackAlgorithmsOmitMasterOnlyKeys() {
        let config = makeConfig(channels: 2)
        config.sharedOptions.levelerEnabled = true
        config.sharedOptions.levelerStrength = 80
        config.sharedOptions.noiseEnabled = true
        config.sharedOptions.noiseMethod = 2            // dynamic
        config.sharedOptions.loudnessEnabled = true     // master-only, must not leak

        let algorithms = try! #require(config.multitrackTrackAlgorithms["Ch_1_BOOM"])

        #expect(algorithms["levelerstrength"] as? Int == 80)
        #expect(algorithms["compressor"] as? String == "auto")
        #expect(algorithms["denoise"] as? Bool == true)
        #expect(algorithms["denoisemethod"] as? String == "dynamic")

        // Master-only keys must not appear per track
        #expect(algorithms["normloudness"] == nil)
        #expect(algorithms["loudnesstarget"] == nil)
        #expect(algorithms["leveler"] == nil)
    }

    @Test func perChannelSettingsAreUsedWhenUnlinked() {
        let config = makeConfig(channels: 2)
        config.linkedSettings = false
        config.channels[0].options.levelerEnabled = true
        config.channels[0].options.levelerStrength = 60
        config.channels[1].options.levelerEnabled = false

        let boom = try! #require(config.multitrackTrackAlgorithms["Ch_1_BOOM"])
        let lavmix = try! #require(config.multitrackTrackAlgorithms["Ch_2_LAVMIX"])

        #expect(boom["levelerstrength"] as? Int == 60)
        #expect(lavmix["levelerstrength"] as? Int == 0)
        #expect(lavmix["compressor"] as? String == "off")
    }
}

// MARK: - Master Options

struct MultitrackMasterOptionsTests {

    @Test func defaultsEnableLevelerGatesAndLoudness() {
        let master = MultitrackMasterOptions()
        let settings = master.getSettings()

        #expect(settings["leveler"] as? Bool == true)
        #expect(settings["gate"] as? Bool == true)
        #expect(settings["crossgate"] as? Bool == true)
        #expect(settings["normloudness"] as? Bool == true)
        #expect(settings["loudnesstarget"] as? Int == -16)
        #expect(settings["loudnessmethod"] as? String == "program")
    }

    @Test func broadcastParametersOnlyWhenEnabled() {
        let master = MultitrackMasterOptions()
        #expect(master.getSettings()["maxlra"] == nil)

        master.broadcastMode = true
        master.maxLRA = 8
        master.maxShortTerm = 5
        master.maxMomentary = 10

        let settings = master.getSettings()
        #expect(settings["maxlra"] as? Int == 8)
        #expect(settings["maxs"] as? Int == 5)
        #expect(settings["maxm"] as? Int == 10)
    }

    @Test func disabledLoudnessOmitsTargets() {
        let master = MultitrackMasterOptions()
        master.loudnessEnabled = false

        let settings = master.getSettings()
        #expect(settings["normloudness"] as? Bool == false)
        #expect(settings["loudnesstarget"] == nil)
    }

    @Test func widgetStateRoundTrip() {
        let original = MultitrackMasterOptions()
        original.levelerEnabled = false
        original.crossgate = false
        original.loudnessTarget = -23
        original.maxPeak = -2
        original.loudnessMethod = 2

        let restored = MultitrackMasterOptions()
        restored.applyWidgetState(original.getWidgetState())

        #expect(restored.levelerEnabled == false)
        #expect(restored.crossgate == false)
        #expect(restored.loudnessTarget == -23)
        #expect(restored.maxPeak == -2)
        #expect(restored.loudnessMethod == 2)
    }
}

// MARK: - Track Matching

struct TrackMatchingTests {

    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }

    @Test func matchesByTrackIdInFileName() {
        let files = urls(["Ch_3_LAV1.wav", "Ch_1_BOOM.wav", "Ch_2_LAVMIX.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ["Ch_1_BOOM", "Ch_2_LAVMIX", "Ch_3_LAV1"])

        #expect(matched.map(\.lastPathComponent) == ["Ch_1_BOOM.wav", "Ch_2_LAVMIX.wav", "Ch_3_LAV1.wav"])
    }

    @Test func matchesGenericTrackNumbering() {
        // Auphonic names the exported files "Track 1", "Track 2", ...
        let files = urls(["Track 2.wav", "Track 1.wav", "Track 3.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ["boom", "lavmix", "lav1"])

        #expect(matched.map(\.lastPathComponent) == ["Track 1.wav", "Track 2.wav", "Track 3.wav"])
    }

    /// Unnamed channels get ids ch1 … ch10; "ch1" must not grab "ch10.wav"
    /// just because the archive lists it first.
    @Test func exactIdWinsOverSubstringForTenOrMoreChannels() {
        let ids = (1...10).map { "ch\($0)" }
        let files = urls(["ch10.wav", "ch9.wav", "ch8.wav", "ch7.wav", "ch6.wav",
                          "ch5.wav", "ch4.wav", "ch3.wav", "ch2.wav", "ch1.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ids)

        #expect(matched.map(\.lastPathComponent) == ids.map { "\($0).wav" })
    }

    /// Same collision with iXML names such as LAV1 / LAV10, and with the
    /// exported names carrying a prefix and suffix around the id.
    @Test func wholeTokenMatchBeatsSubstringMatch() {
        let files = urls(["take_LAV10_processed.wav", "take_LAV1_processed.wav", "take_BOOM_processed.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ["BOOM", "LAV1", "LAV10"])

        #expect(matched.map(\.lastPathComponent) == ["take_BOOM_processed.wav", "take_LAV1_processed.wav", "take_LAV10_processed.wav"])
    }

    /// Ids glued to other text still match, and the longer id is tried first
    @Test func substringFallbackPrefersLongerIds() {
        let files = urls(["mixlav10x.wav", "mixlav1x.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ["lav1", "lav10"])

        #expect(matched.map(\.lastPathComponent) == ["mixlav1x.wav", "mixlav10x.wav"])
    }

    @Test func fallsBackToNameOrder() {
        let files = urls(["b.wav", "a.wav"])
        let matched = BatchWorkflow.matchTracks(files, to: ["first", "second"])

        #expect(matched.count == 2)
        #expect(matched.map(\.lastPathComponent) == ["a.wav", "b.wav"])
    }
}

// MARK: - Zip Reading

struct ZipArchiveTests {

    /// Build a zip with the system zip tool so we test against a real archive
    private func makeZip(files: [String: Data]) throws -> (zip: URL, workDir: URL)? {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip_test_\(UUID().uuidString)", isDirectory: true)
        let contents = workDir.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        for (name, data) in files {
            try data.write(to: contents.appendingPathComponent(name))
        }

        let zipURL = workDir.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", zipURL.path, "."]
        process.currentDirectoryURL = contents
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            return nil      // /usr/bin/zip unavailable (sandboxed CI) — skip
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: workDir)
            return nil
        }
        return (zipURL, workDir)
    }

    @Test func extractsDeflatedAndStoredEntries() throws {
        // Compressible text + incompressible random bytes (stored)
        let text = Data(String(repeating: "Auphonic multitrack export. ", count: 500).utf8)
        var random = Data(count: 4096)
        random.withUnsafeMutableBytes { buffer in
            for index in 0..<buffer.count { buffer[index] = UInt8(index % 251) }
        }

        guard let made = try makeZip(files: ["Track 1.wav": text, "Track 2.wav": random]) else { return }
        defer { try? FileManager.default.removeItem(at: made.workDir) }

        let output = made.workDir.appendingPathComponent("out", isDirectory: true)
        let extracted = try ZipArchive.extract(made.zip, to: output)

        #expect(extracted.count == 2)

        let byName = Dictionary(uniqueKeysWithValues: extracted.map { ($0.lastPathComponent, $0) })
        #expect(try Data(contentsOf: try #require(byName["Track 1.wav"])) == text)
        #expect(try Data(contentsOf: try #require(byName["Track 2.wav"])) == random)
    }

    // MARK: Hand-built archives (no dependency on /usr/bin/zip)

    /// Minimal stored-only zip writer. `streamed` entries get general-purpose
    /// flag bit 3: zero sizes in the local header and a trailing data
    /// descriptor, which is how Auphonic's server-side zips look.
    private func buildStoredZip(_ files: [(name: String, data: Data, streamed: Bool)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

        var out: [UInt8] = []
        var central: [UInt8] = []

        for file in files {
            let name = Array(file.name.utf8)
            let flags = file.streamed ? 0x0008 : 0
            let localOffset = out.count
            let sizes = file.streamed ? le32(0) + le32(0) : le32(file.data.count) + le32(file.data.count)

            out += le32(0x0403_4b50) + le16(20) + le16(flags) + le16(0) + le16(0) + le16(0)
            out += le32(0) + sizes + le16(name.count) + le16(0) + name
            out += Array(file.data)
            if file.streamed {
                out += le32(0x0807_4b50) + le32(0) + le32(file.data.count) + le32(file.data.count)
            }

            central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(flags) + le16(0) + le16(0) + le16(0)
            central += le32(0) + le32(file.data.count) + le32(file.data.count)
            central += le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            central += le32(localOffset) + name
        }

        let directoryOffset = out.count
        out += central
        out += le32(0x0605_4b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        out += le32(central.count) + le32(directoryOffset) + le16(0)
        return Data(out)
    }

    private func extract(_ zip: Data) throws -> [String: Data] {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let archive = workDir.appendingPathComponent("archive.zip")
        try zip.write(to: archive)
        let written = try ZipArchive.extract(archive, to: workDir.appendingPathComponent("out", isDirectory: true))
        return try Dictionary(uniqueKeysWithValues: written.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    /// A streamed entry used to come back as "everything up to the end of the
    /// archive": descriptor, following entries and central directory included.
    @Test func streamedEntriesUseCentralDirectorySizes() throws {
        let one = Data(repeating: 0xA1, count: 1500)
        let two = Data(repeating: 0xB2, count: 700)
        let zip = buildStoredZip([("ch1.wav", one, true), ("ch2.wav", two, true)])

        let files = try extract(zip)
        #expect(files.count == 2)
        #expect(files["ch1.wav"] == one)
        #expect(files["ch2.wav"] == two)
    }

    @Test func plainStoredEntriesStillExtract() throws {
        let one = Data("first".utf8)
        let empty = Data()
        let zip = buildStoredZip([("a.txt", one, false), ("empty.txt", empty, false), ("b.txt", Data("b".utf8), true)])

        let files = try extract(zip)
        #expect(files["a.txt"] == one)
        #expect(files["empty.txt"] == empty)
        #expect(files["b.txt"] == Data("b".utf8))
    }

    @Test func rejectsNonZipData() throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not_a_zip_\(UUID().uuidString).zip")
        try Data("this is not a zip file".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("out_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(throws: ZipArchiveError.self) {
            try ZipArchive.extract(bogus, to: output)
        }
    }
}
