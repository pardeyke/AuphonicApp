import Testing
import Foundation
@testable import AuphonicApp

// MARK: - Production Mode & Job Counts

struct ProductionModeTests {

    private func makeConfig(channels: Int, bitDepth: Int = 24) -> ChannelConfig {
        let config = ChannelConfig()
        config.configure(count: channels, trackNames: ["BOOM", "LAVMIX", "LAV1", "LAV2"], bitDepth: bitDepth)
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
        let files = config.multitrackOutputFiles
        #expect(files.count == 1)
        #expect(files[0]["format"] as? String == "tracks")
        #expect(files[0]["ending"] as? String == "wav.zip")
    }

    @Test func mixdownIsRequestedAsMonoWhenEnabled() {
        let config = makeConfig(channels: 2, bitDepth: 32)
        config.downloadMixdown = true

        let files = config.multitrackOutputFiles
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
