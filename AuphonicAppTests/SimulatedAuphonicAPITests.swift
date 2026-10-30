import Testing
import Foundation
import AVFoundation
@testable import AuphonicApp

/// The offline Auphonic the UI tests run against has to be right itself:
/// its archives must open with the app's own ZIP reader, its outputs must
/// be the scaled input in the requested format, and its failure switches
/// must do what the UI tests assume.
struct SimulatedAuphonicAPITests {

    private func makeWorkDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim_api_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeMono(seconds: Double = 0.5, value: Float = 0.4) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sim_in_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = value }
        try file.write(from: buffer)
        return url
    }

    private func readAll(_ url: URL) throws -> (format: AVAudioFormat, samples: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        return (file.fileFormat, samples)
    }

    // MARK: Scenario flags

    @Test func scenarioParsesFlags() {
        let scenario = SimulatedAuphonicAPI.Scenario("processingError, transientErrors=3,failTitle=take_02,failTitle=x,createFails")
        #expect(scenario.processingError)
        #expect(scenario.transientErrors == 3)
        #expect(scenario.failingTitles == ["take_02", "x"])
        #expect(scenario.createFails)
        #expect(!scenario.revokedToken)
        #expect(!SimulatedAuphonicAPI.Scenario("").processingError)
        #expect(SimulatedAuphonicAPI.Scenario("transientErrors").transientErrors == 2)
    }

    // MARK: Stored ZIP

    @Test func storedZipOpensWithTheAppsReader() throws {
        let work = makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let one = work.appendingPathComponent("Ch_1_BOOM.wav")
        let two = work.appendingPathComponent("Ch_2_LAV.wav")
        try Data((0..<5000).map { UInt8($0 % 251) }).write(to: one)
        try Data("second".utf8).write(to: two)

        let archive = work.appendingPathComponent("tracks.zip")
        try StoredZipWriter.write([one, two], to: archive)

        let out = work.appendingPathComponent("out", isDirectory: true)
        let extracted = try ZipArchive.extract(archive, to: out)
        #expect(extracted.map(\.lastPathComponent) == ["Ch_1_BOOM.wav", "Ch_2_LAV.wav"])
        #expect(try Data(contentsOf: extracted[0]) == Data(contentsOf: one))
        #expect(try Data(contentsOf: extracted[1]) == Data(contentsOf: two))
    }

    @Test func crc32MatchesTheReferenceValue() {
        // "123456789" is the standard CRC-32 check vector
        #expect(StoredZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926)
        #expect(StoredZipWriter.crc32(Data()) == 0)
    }

    // MARK: Productions

    @Test func singletrackReturnsTheScaledInputInTheRequestedFormat() async throws {
        let work = makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let api = SimulatedAuphonicAPI(workDirectory: work)
        api.token = "t"
        let input = try makeMono()
        defer { try? FileManager.default.removeItem(at: input) }

        let uuid = try await api.createProduction(
            presetUuid: "", manualSettings: ["output_files": [["format": "wav-16bit"]]], title: "take")
        try await api.uploadFile(productionUuid: uuid, file: input)
        try await api.startProduction(productionUuid: uuid)

        var status = try await api.getProductionStatus(productionUuid: uuid)
        var polls = 1
        while !status.isDone {
            status = try await api.getProductionStatus(productionUuid: uuid)
            polls += 1
        }
        #expect(polls == 3, "done on the third poll")
        #expect(status.outputFileUrl.hasSuffix("output.wav"))

        let downloaded = try await api.downloadFile(from: status.outputFileUrl)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let (format, samples) = try readAll(downloaded)
        #expect(format.channelCount == 1)
        #expect(format.streamDescription.pointee.mBitsPerChannel == 16)
        #expect(samples.count == 24_000)
        #expect(abs((samples.first ?? 0) - 0.4 * SimulatedAuphonicAPI.processingGain) < 1e-4)

        // The log is JSON the test runner can read; intermediate polls are not logged
        let log = try JSONSerialization.jsonObject(with: Data(contentsOf: api.logURL)) as? [[String: Any]]
        #expect(log?.map { $0["call"] as? String } == ["createProduction", "upload", "start", "status", "download"])
        #expect(log?[3]["result"] as? String == "done")
        let upload = log?[1]["files"] as? [[String: Any]]
        #expect(upload?.first?["channels"] as? Int == 1)
        #expect(upload?.first?["frames"] as? Int == 24_000)
    }

    @Test func multitrackDeliversSixteenBitTracksAndAMonoMixdown() async throws {
        let work = makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let api = SimulatedAuphonicAPI(workDirectory: work)
        api.token = "t"
        let boom = work.appendingPathComponent("BOOM.wav")
        let lav = work.appendingPathComponent("LAV.wav")
        try FileManager.default.copyItem(at: makeMono(value: 0.4), to: boom)
        try FileManager.default.copyItem(at: makeMono(value: 0.2), to: lav)

        let uuid = try await api.createMultitrackProduction(
            trackIds: ["BOOM", "LAV"], trackAlgorithms: [:], masterAlgorithms: [:],
            outputFiles: [["format": "tracks", "ending": "wav.zip"], ["format": "wav-24bit", "mono_mixdown": true]],
            title: "scene")
        try await api.uploadFiles(productionUuid: uuid, files: [(fieldName: "BOOM", file: boom), (fieldName: "LAV", file: lav)])
        var status = try await api.getProductionStatus(productionUuid: uuid)
        while !status.isDone { status = try await api.getProductionStatus(productionUuid: uuid) }

        #expect(status.outputFiles.count == 2)
        let tracks = try #require(status.outputFiles.first(where: { $0.isTracksArchive }))
        let archive = try await api.downloadFile(from: tracks.downloadUrl)
        let unpacked = try ZipArchive.extract(archive, to: work.appendingPathComponent("unpacked", isDirectory: true))
        #expect(unpacked.map(\.lastPathComponent) == ["BOOM.wav", "LAV.wav"])
        let (trackFormat, trackSamples) = try readAll(unpacked[0])
        #expect(trackFormat.streamDescription.pointee.mBitsPerChannel == 16)
        #expect(abs((trackSamples.first ?? 0) - 0.2) < 1e-4)

        let mixdown = try #require(status.outputFiles.first(where: { !$0.isTracksArchive }))
        let mixdownFile = try await api.downloadFile(from: mixdown.downloadUrl)
        let (mixFormat, mixSamples) = try readAll(mixdownFile)
        #expect(mixFormat.channelCount == 1)
        #expect(mixFormat.streamDescription.pointee.mBitsPerChannel == 24)
        #expect(abs((mixSamples.first ?? 0) - (0.2 + 0.1) / 2) < 1e-5, "mixdown is the average of the processed tracks")
    }

    @Test func failureSwitchesBehaveLikeTheUITestsAssume() async throws {
        let work = makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let input = try makeMono(seconds: 0.1)
        defer { try? FileManager.default.removeItem(at: input) }

        // Title-specific failure
        let partial = SimulatedAuphonicAPI(scenario: .init("failTitle=take_02"), workDirectory: work)
        partial.token = "t"
        let good = try await partial.createProduction(presetUuid: "", manualSettings: [:], title: "take_01 Ch 1")
        let bad = try await partial.createProduction(presetUuid: "", manualSettings: [:], title: "take_02 Ch 1")
        try await partial.uploadFile(productionUuid: good, file: input)
        try await partial.uploadFile(productionUuid: bad, file: input)
        #expect(try await partial.getProductionStatus(productionUuid: bad).isError)
        #expect(!(try await partial.getProductionStatus(productionUuid: good).isError))

        // Transient errors clear after N polls
        let flaky = SimulatedAuphonicAPI(scenario: .init("transientErrors=2"), workDirectory: work)
        flaky.token = "t"
        let uuid = try await flaky.createProduction(presetUuid: "", manualSettings: [:], title: "x")
        for _ in 0..<2 {
            await #expect(throws: URLError.self) { try await flaky.getProductionStatus(productionUuid: uuid) }
        }
        _ = try await flaky.getProductionStatus(productionUuid: uuid)

        // Revoked token is the non-retryable error the workflow recognizes
        let revoked = SimulatedAuphonicAPI(scenario: .init("revokedToken"), workDirectory: work)
        revoked.token = "t"
        let r = try await revoked.createProduction(presetUuid: "", manualSettings: [:], title: "x")
        await #expect(throws: AuphonicAPIClient.APIError.self) { try await revoked.getProductionStatus(productionUuid: r) }
        do {
            _ = try await revoked.getProductionStatus(productionUuid: r)
        } catch {
            #expect(!BatchWorkflow.isRetryablePollError(error))
        }

        // No token: every call is refused, like the real client
        let anonymous = SimulatedAuphonicAPI(workDirectory: work)
        await #expect(throws: AuphonicAPIClient.APIError.self) { _ = try await anonymous.fetchUserInfo() }
    }

    @Test func presetsAndCreditsAreStable() async throws {
        let work = makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let api = SimulatedAuphonicAPI(workDirectory: work)
        api.token = "t"

        let credits = try await api.fetchUserInfo()
        #expect(credits.displayCredits == 10)
        #expect(try await api.fetchPresets().map(\.name) == ["UITest Dialog", "UITest Music"])
        let details = try await api.fetchPresetDetails(uuid: "preset-dialog")
        #expect((details["algorithms"] as? [String: Any])?["leveler"] as? Bool == true)

        let uuid = try await api.savePreset(name: "Mine", settings: ["algorithms": ["leveler": true]])
        #expect(try await api.fetchPresets().last == AuphonicPreset(uuid: uuid, name: "Mine"))
    }
}
