import Testing
import Foundation
import AVFoundation
@testable import AuphonicApp

/// End-to-end runs of `BatchWorkflow` against `MockAuphonicAPI`: real
/// extraction, real ZIP unpacking and real channel write-back, only the
/// network is faked.
@MainActor
struct BatchWorkflowTests {

    // MARK: Fixtures

    private struct Scene {
        let api = MockAuphonicAPI()
        let workflow: BatchWorkflow
        let destination: URL
        let sourceDirectory: URL

        init() {
            workflow = BatchWorkflow(apiClient: api)
            workflow.pollInterval = .milliseconds(5)
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("wf_\(UUID().uuidString)", isDirectory: true)
            destination = base.appendingPathComponent("out", isDirectory: true)
            sourceDirectory = base.appendingPathComponent("src", isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            for url in api.downloadsReturned { try? FileManager.default.removeItem(at: url) }
        }

        /// A take in the source folder with one constant value per channel
        func take(named name: String, channels: Int, bitDepth: Int = 24, isFloat: Bool = false,
                  value: @escaping (Int) -> Float) throws -> BatchFile {
            let url = sourceDirectory.appendingPathComponent(name)
            try makeWav(url: url, channels: channels, bitDepth: bitDepth, isFloat: isFloat, channelValue: value)
            guard let file = BatchFile(url: url) else { throw NSError(domain: "test", code: 1) }
            return file
        }

        func outputFiles() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        }

        func waitUntilFinished() async {
            for _ in 0..<2000 where workflow.isRunning {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// Mono processed audio as it would come back from Auphonic
    private func processedMono(_ value: Float, bitDepth: Int = 24, isFloat: Bool = false) throws -> Data {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 1, bitDepth: bitDepth, isFloat: isFloat) { _ in value }
        return try Data(contentsOf: url)
    }

    private func singletrackGroup(for file: BatchFile, configure: (ChannelConfig) -> Void) -> [FileGroup] {
        let groups = FileGrouper.makeGroups(from: [file])
        configure(groups[0].config)
        return groups
    }

    // MARK: Standard mode

    @Test func standardModeSavesProcessedFileUnderOriginalName() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "interview.wav", channels: 1) { _ in 0.3 }
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-1")] = try processedMono(0.6)

        scene.workflow.start(files: [file], config: config, destination: scene.destination)
        await scene.waitUntilFinished()

        let expected = scene.destination.appendingPathComponent("interview.wav")
        #expect(file.status == .done(expected))
        #expect(try scene.outputFiles() == ["interview.wav"])
        #expect(abs(try readChannel(expected, channel: 0)[0] - 0.6) < 1e-5)

        let production = try #require(scene.api.production("prod-1"))
        #expect(production.title == "interview")
        #expect(production.started)
        #expect(production.settings["output_files"] == nil)                  // keep format
        #expect(production.uploads.map(\.fieldName) == ["input_file"])
        #expect(production.uploads[0].file == file.url)                      // whole file, no extraction
        #expect(scene.api.deleted.isEmpty)
        #expect(scene.workflow.statusText.hasPrefix("Done"))
        #expect(!FileManager.default.fileExists(atPath: scene.api.downloadsReturned[0].path))   // temp download removed
    }

    @Test func housekeepingDeletesProductionsOnlyAfterSuccess() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "a.wav", channels: 1) { _ in 0.3 }
        let config = StandardModeConfig()
        config.options.noiseEnabled = true
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-1")] = try processedMono(0.1)
        scene.workflow.deleteProductionsAfterDownload = true

        scene.workflow.start(files: [file], config: config, destination: scene.destination)
        await scene.waitUntilFinished()

        #expect(scene.api.deleted == ["prod-1"])
    }

    // MARK: Mix Preparation, singletrack

    @Test func singletrackPatchesOnlySelectedChannelsAndCleansUp() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "take.wav", channels: 3) { ch in Float(ch + 1) * 0.1 }
        let groups = singletrackGroup(for: file) { config in
            config.channels[1].enabled = false            // channel 2 stays untouched
            config.sharedOptions.levelerEnabled = true
            config.selectedPresetUuid = "podcast-preset"
        }
        // Productions are created in channel order: prod-1 = Ch 1, prod-2 = Ch 3
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-1")] = try processedMono(0.7)
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-2")] = try processedMono(-0.5)

        scene.workflow.start(groups: groups, destination: scene.destination)
        await scene.waitUntilFinished()

        let output = scene.destination.appendingPathComponent("take.wav")
        #expect(file.status == .done(output))
        #expect(abs(try readChannel(output, channel: 0)[0] - 0.7) < 1e-5)
        #expect(try readChannel(output, channel: 1) == readChannel(file.url, channel: 1))
        #expect(abs(try readChannel(output, channel: 2)[0] - (-0.5)) < 1e-5)

        #expect(scene.api.productions.count == 2)
        for production in scene.api.productions {
            #expect(production.uploads.count == 1)
            #expect(production.uploads[0].channels == 1)                     // mono per channel
            #expect(production.presetUuid == "podcast-preset")
            let files = production.settings["output_files"] as? [[String: Any]]
            #expect(files?.first?["format"] as? String == "wav-24bit")
            let algorithms = production.settings["algorithms"] as? [String: Any]
            #expect(algorithms?["silence_cutter"] as? Bool == false)          // preset cutters neutralised
            #expect(!FileManager.default.fileExists(atPath: production.uploads[0].file.path))   // extracted mono removed
        }
        for download in scene.api.downloadsReturned {
            #expect(!FileManager.default.fileExists(atPath: download.path))
        }
        #expect(try Data(contentsOf: file.url).count > 0)                    // original untouched
    }

    // MARK: Mix Preparation, multitrack

    @Test func multitrackMapsTracksBackAndWritesMixdown() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "scene.wav", channels: 3) { _ in 0.05 }
        let groups = singletrackGroup(for: file) { config in
            config.productionMode = .multitrack
            config.downloadMixdown = true
            config.mixdownTargetChannel = 1                     // 0-based: the mixdown lands in channel 2
        }
        // Track ids for unnamed channels are Ch_1 … Ch_3; the archive lists them out of order
        let zip = buildStoredZip([
            ("Ch_3.wav", try processedMono(0.6, bitDepth: 16), true),
            ("Ch_1.wav", try processedMono(0.4, bitDepth: 16), true),
            ("Ch_2.wav", try processedMono(0.5, bitDepth: 16), false)
        ])
        scene.api.downloadContent[MockAuphonicAPI.tracksURL("prod-1")] = zip
        scene.api.downloadContent[MockAuphonicAPI.mixdownURL("prod-1")] = try processedMono(0.9)

        scene.workflow.start(groups: groups, destination: scene.destination)
        await scene.waitUntilFinished()

        let output = scene.destination.appendingPathComponent("scene.wav")
        #expect(file.status == .done(output))
        #expect(abs(try readChannel(output, channel: 0)[0] - 0.4) < 1e-4)
        #expect(abs(try readChannel(output, channel: 1)[0] - 0.9) < 1e-5)   // mixdown overwrote channel 2
        #expect(abs(try readChannel(output, channel: 2)[0] - 0.6) < 1e-4)

        let production = try #require(scene.api.production("prod-1"))
        #expect(production.isMultitrack)
        #expect(production.trackIds == ["Ch_1", "Ch_2", "Ch_3"])
        #expect(production.uploads.map(\.fileName) == ["Ch_1.wav", "Ch_2.wav", "Ch_3.wav"])   // named for Auphonic
        #expect(production.uploads.allSatisfy { $0.channels == 1 })
        let uploadFolder = production.uploads[0].file.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: uploadFolder.path))                 // private folder removed
    }

    // MARK: Cancellation and failures

    @Test func cancelResetsTheFileAndLeavesNoOutput() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "long.wav", channels: 2) { _ in 0.2 }
        let groups = singletrackGroup(for: file) { $0.sharedOptions.levelerEnabled = true }
        scene.api.pollsUntilDone = .max      // never finishes on its own

        scene.workflow.start(groups: groups, destination: scene.destination)
        try await Task.sleep(for: .milliseconds(80))
        #expect(scene.workflow.isRunning)
        scene.workflow.cancel()
        await scene.waitUntilFinished()

        #expect(file.status == .pending)
        #expect(scene.workflow.statusText.hasPrefix("Cancelled"))
        #expect(try scene.outputFiles().isEmpty)
        for production in scene.api.productions {
            for upload in production.uploads {
                #expect(!FileManager.default.fileExists(atPath: upload.file.path))
            }
        }
    }

    @Test func processingErrorFailsTheFileWithAuphonicsMessage() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "bad.wav", channels: 1) { _ in 0.2 }
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        scene.api.failProcessingWith = "Input file corrupt"

        scene.workflow.start(files: [file], config: config, destination: scene.destination)
        await scene.waitUntilFinished()

        guard case .failed(let message) = file.status else {
            Issue.record("expected failed, got \(file.status)"); return
        }
        #expect(message.contains("Input file corrupt"))
        #expect(scene.workflow.statusText.contains("1 of 1 files failed"))
        #expect(try scene.outputFiles().isEmpty)
        #expect(scene.api.deleted.isEmpty)
    }

    @Test func revokedTokenFailsWithinOnePollInsteadOfAnHour() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "t.wav", channels: 1) { _ in 0.2 }
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        scene.api.pollsUntilDone = .max
        scene.api.statusError = AuphonicAPIClient.APIError.invalidToken

        scene.workflow.start(files: [file], config: config, destination: scene.destination)
        await scene.waitUntilFinished()

        guard case .failed(let message) = file.status else {
            Issue.record("expected failed, got \(file.status)"); return
        }
        #expect(message == "Invalid API token")
        #expect(scene.api.production("prod-1")?.polls == 1)
    }

    @Test func transientPollErrorsAreRetried() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "flaky.wav", channels: 1) { _ in 0.2 }
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        scene.api.transientStatusErrors = 3
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-1")] = try processedMono(0.25)

        scene.workflow.start(files: [file], config: config, destination: scene.destination)
        await scene.waitUntilFinished()

        #expect(file.status == .done(scene.destination.appendingPathComponent("flaky.wav")))
        #expect(scene.api.production("prod-1")?.polls == 4)
    }

    /// One failing channel job must not leave the other job's files behind
    @Test func failedJobCleansUpItsSiblingsFiles() async throws {
        let scene = Scene()
        defer { scene.tearDown() }
        let file = try scene.take(named: "pair.wav", channels: 2) { _ in 0.2 }
        let groups = singletrackGroup(for: file) { $0.sharedOptions.levelerEnabled = true }
        // prod-1 downloads fine, prod-2 has no content and fails on download
        scene.api.downloadContent[MockAuphonicAPI.singletrackOutputURL("prod-1")] = try processedMono(0.3)

        scene.workflow.start(groups: groups, destination: scene.destination)
        await scene.waitUntilFinished()

        guard case .failed = file.status else {
            Issue.record("expected failed, got \(file.status)"); return
        }
        #expect(try scene.outputFiles().isEmpty)
        for download in scene.api.downloadsReturned {
            #expect(!FileManager.default.fileExists(atPath: download.path))
        }
        for production in scene.api.productions {
            for upload in production.uploads {
                #expect(!FileManager.default.fileExists(atPath: upload.file.path))
            }
        }
    }
}
