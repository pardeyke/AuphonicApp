import XCTest
import AVFoundation

/// Mix Preparation mode: files are grouped by timecode and channel count,
/// selected channels are processed (singletrack or multitrack) and written
/// back into otherwise bit-identical copies of the originals.
final class MixPreparationUITests: AppUITestCase {

    private let fieldNames = ["BOOM", "LAVMIX", "LAV1", "LAV2"]

    /// Four-channel 32-bit float take like a MixPre's, with a padding chunk
    private func fourChannelTake(minute: Int) -> WavFixture {
        WavFixture(channels: 4, format: .float32, seconds: 2,
                   timeReference: WavFixture.timeReference(h: 9, m: minute, s: 0),
                   trackNames: fieldNames,
                   extraChunks: [(id: "PAD ", data: Data(count: 1000))])
    }

    // MARK: - Grouping

    func testFilesAreGroupedByTimecodeAndChannelCount() throws {
        makeSession(mode: .mixPreparation)
        let names = ["BOOM", "LAV1", "LAV2"]
        try session.makeWav("A.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 10, m: 0, s: 0), trackNames: names))
        try session.makeWav("B.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 10, m: 5, s: 0), trackNames: names))
        try session.makeWav("C.wav", WavFixture(channels: 2, seconds: 1, timeReference: WavFixture.timeReference(h: 11, m: 0, s: 0)))
        // Name sorts first, timecode sorts last: grouping follows the timecode
        try session.makeWav("0_late.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 12, m: 0, s: 0), trackNames: names))
        session.launch()

        XCTAssertTrue(session.element("detail.emptyState").exists)
        session.addFiles(expectedCount: 4)

        XCTAssertEqual(groupTimecode(1), "10:00:00–10:05:00")
        XCTAssertEqual(groupSummary(1), "3 ch · 2 files · Singletrack")
        XCTAssertEqual(groupTimecode(2), "11:00:00")
        XCTAssertEqual(groupSummary(2), "2 ch · 1 file · Singletrack")
        XCTAssertEqual(groupTimecode(3), "12:00:00")
        XCTAssertFalse(session.group(4).exists)

        // Nothing configured yet: every group carries the warning
        for index in 1...3 {
            XCTAssertTrue(session.group(index).descendants(matching: .any)["group.unconfigured"].exists)
        }

        // The first take is selected, so the first group is configured;
        // iXML names label the channels
        XCTAssertEqual(session.element("channel.1").label, "Ch 1 (BOOM)")
        XCTAssertEqual(session.element("channel.3").label, "Ch 3 (LAV2)")

        // Selecting the stereo group shows its own channels
        session.selectGroup(2)
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("channel.1").label == "Ch 1 (Left)" })
        XCTAssertFalse(session.element("channel.3").exists)

        // Configuring one group clears only its warning
        session.setCard("Adaptive Leveler", on: true)
        XCTAssertFalse(session.group(2).descendants(matching: .any)["group.unconfigured"].exists)
        XCTAssertTrue(session.group(1).descendants(matching: .any)["group.unconfigured"].exists)

        // Collapse one group, then all
        session.group(1).descendants(matching: .any)["group.collapse"].click()
        XCTAssertTrue(session.waitUntil(timeout: 3) { !self.session.fileRow("A").exists })
        XCTAssertTrue(session.fileRow("C").exists)
        session.element("sidebar.collapseAll").click()
        XCTAssertTrue(session.waitUntil(timeout: 3) { !self.session.fileRow("C").exists })
        session.element("sidebar.collapseAll").click()
        XCTAssertTrue(session.waitUntil(timeout: 3) { self.session.fileRow("A").exists && self.session.fileRow("C").exists })

        // Without the stereo take in between, the three-channel runs merge
        session.group(2).descendants(matching: .any)["group.timecode"].firstMatch.rightClick()
        let remove = app.menuItems["Remove Group"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "group context menu did not open")
        remove.click()
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("sidebar.fileCount").stringValue == "3 files" })
        XCTAssertEqual(groupTimecode(1), "10:00:00–12:00:00")
        XCTAssertEqual(groupSummary(1), "3 ch · 3 files · Singletrack")
    }

    func testSwitchingFromStandardDropsNonWavFiles() throws {
        makeSession(mode: .standard)
        _ = try makeStereoTakes(1)
        try writeAiff(named: "interview.aiff")
        session.launch()
        session.addFiles(expectedCount: 2)
        XCTAssertEqual(Set(session.rowNames), ["take_01", "interview"])

        session.switchMode(to: .mixPreparation)
        session.dismissAlert(containing: "1 non-WAV file was removed")
        XCTAssertEqual(session.rowNames, ["take_01"])
        XCTAssertTrue(session.group(1).exists, "Mix Preparation shows groups")

        // And back: Standard mode shows the flat list again
        session.switchMode(to: .standard)
        XCTAssertFalse(session.group(1).exists)
        XCTAssertEqual(session.rowNames, ["take_01"])
    }

    // MARK: - Singletrack

    func testSingletrackPatchesOnlyTheSelectedChannels() throws {
        makeSession(mode: .mixPreparation)
        let originals = [
            try session.makeWav("scene12_take1.wav", fourChannelTake(minute: 0)),
            try session.makeWav("scene12_take2.wav", fourChannelTake(minute: 3))
        ]
        session.launch()
        session.addFiles(expectedCount: 2)

        session.setCheckbox("channel.2", on: false)
        session.setCheckbox("channel.4", on: false)
        session.setCard("Adaptive Leveler", on: true)
        session.setCard("Noise & Reverb Reduction", on: true)
        XCTAssertEqual(session.uploadPlan, "2 productions per file: Ch 1, Ch 3")
        XCTAssertEqual(session.element("credits.productions").stringValue,
                       "4 productions — Auphonic bills a 3 minute minimum each")

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 2 files processed")
        XCTAssertEqual(session.outputNames, ["scene12_take1.wav", "scene12_take2.wav"])

        for original in originals {
            try assertMixPrepOutput(
                original: original,
                output: session.outputDirectory.appendingPathComponent(original.lastPathComponent),
                channels: [.processed(bits: 24), .untouched, .processed(bits: 24), .untouched])
        }

        // One mono production per selected channel, never a shared upload
        let creates = session.apiCalls("createProduction")
        XCTAssertEqual(creates.map(\.title).sorted(), [
            "scene12_take1 Ch 1", "scene12_take1 Ch 3", "scene12_take2 Ch 1", "scene12_take2 Ch 3"])
        for create in creates {
            XCTAssertEqual(create.outputFormat, "wav-24bit", "float sources come back as 24-bit WAV")
            XCTAssertEqual(create.algorithms["leveler"] as? Bool, true)
            XCTAssertEqual(create.algorithms["denoise"] as? Bool, true)
            XCTAssertEqual(create.algorithms["cutsilence"] as? Bool ?? false, false, "cutters are forced off")
        }
        for upload in session.apiCalls("upload").flatMap(\.uploadedFiles) {
            XCTAssertEqual(upload["channels"] as? Int, 1)
            XCTAssertEqual(upload["isFloat"] as? Bool, true, "extraction keeps 32-bit float")
            XCTAssertEqual(upload["frames"] as? Int, 2 * 48_000)
        }
        XCTAssertEqual(session.fileState("scene12_take1"), "done")
    }

    func testSixteenBitTakesRequestSixteenBitWav() throws {
        makeSession(mode: .mixPreparation)
        let original = try session.makeWav("dialog.wav", WavFixture(channels: 2, format: .int16, seconds: 2,
                                                                     timeReference: WavFixture.timeReference(h: 14, m: 0, s: 0)))
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCheckbox("channel.2", on: false)
        session.setCard("Filtering", on: true)
        session.pick("Voice AutoEQ", in: "picker.Method", card: "Filtering")

        session.processBatch()
        session.waitForBatchToFinish()

        let create = try XCTUnwrap(session.apiCalls("createProduction").first)
        XCTAssertEqual(create.outputFormat, "wav-16bit")
        XCTAssertEqual(create.algorithms["filtermethod"] as? String, "autoeq")
        try assertMixPrepOutput(original: original,
                                output: session.outputDirectory.appendingPathComponent("dialog.wav"),
                                channels: [.processed(bits: 16), .untouched])
    }

    func testUnlinkedSettingsGiveEveryChannelItsOwnProduction() throws {
        makeSession(mode: .mixPreparation)
        try session.makeWav("take.wav", WavFixture(channels: 2, format: .int24, seconds: 1,
                                                   timeReference: WavFixture.timeReference(h: 8, m: 0, s: 0),
                                                   trackNames: ["BOOM", "LAV"]))
        session.launch()
        session.addFiles(expectedCount: 1)

        session.setCheckbox("checkbox.Link settings", on: false)
        XCTAssertFalse(session.element("preset.picker").exists, "presets only apply to linked settings")

        session.element("channelTab.1").click()
        session.setCard("Adaptive Leveler", on: true)

        // Channel 2 has nothing switched on yet: the group is not ready
        session.element("toolbar.processBatch").click()
        session.dismissAlert(containing: "Please enable at least one channel and select a preset or processing options.")

        session.element("channelTab.2").click()
        let levelerOnTab2 = session.card("Adaptive Leveler").descendants(matching: .any)["card.toggle"].firstMatch
        XCTAssertTrue(session.waitUntil(timeout: 3) { !levelerOnTab2.isOn }, "channel 2 has its own settings")
        session.setCard("Loudness Normalization", on: true)

        session.processBatch()
        session.waitForBatchToFinish()

        let creates = Dictionary(uniqueKeysWithValues: session.apiCalls("createProduction").map { ($0.title, $0) })
        let first = try XCTUnwrap(creates["take Ch 1"])
        let second = try XCTUnwrap(creates["take Ch 2"])
        XCTAssertEqual(first.algorithms["leveler"] as? Bool, true)
        XCTAssertEqual(first.algorithms["normloudness"] as? Bool, false)
        XCTAssertEqual(second.algorithms["leveler"] as? Bool, false)
        XCTAssertEqual(second.algorithms["normloudness"] as? Bool, true)
    }

    func testProcessRunsOnlyTheSelectedTake() throws {
        makeSession(mode: .mixPreparation)
        _ = try makeStereoTakes(3)
        session.launch()
        session.addFiles(expectedCount: 3)
        session.setCard("Adaptive Leveler", on: true)

        session.selectFile("take_02")
        session.processSelected()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 file processed")
        XCTAssertEqual(session.outputNames, ["take_02.wav"])
        XCTAssertEqual(session.fileState("take_01"), "pending")
        XCTAssertEqual(session.fileState("take_02"), "done")
        XCTAssertEqual(session.fileState("take_03"), "pending")
    }

    // MARK: - Multitrack

    func testMultitrackWritesTracksBackAndTheMixdownIntoItsChannel() throws {
        makeSession(mode: .mixPreparation)
        let original = try session.makeWav("scene3.wav", fourChannelTake(minute: 30))
        session.launch()
        session.addFiles(expectedCount: 1)

        session.setProductionMode("Multitrack")
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.groupSummary(1) == "4 ch · 1 file · Multitrack" })
        session.setCard("Noise & Reverb Reduction", on: true)

        session.setCheckbox("checkbox.Also download the master mixdown", on: true)
        session.pick("Ch 4 (LAV2)", in: "mixdown.target")
        XCTAssertTrue(session.element("mixdown.overwriteWarning").waitForExistence(timeout: 3),
                      "channel 4 is still a track, so the mixdown would overwrite it")
        session.setCheckbox("channel.4", on: false)
        XCTAssertTrue(session.element("mixdown.overwriteWarning").waitForNonExistence(timeout: 3))
        XCTAssertEqual(session.uploadPlan, "1 multitrack production per file — 3 tracks + mixdown")

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 file processed")

        // Tracks come back 16-bit; the mixdown 24-bit into channel 4
        try assertMixPrepOutput(original: original,
                                output: session.outputDirectory.appendingPathComponent("scene3.wav"),
                                channels: [.processed(bits: 16), .processed(bits: 16), .processed(bits: 16),
                                           .mixdown(of: [0, 1, 2], bits: 24)])

        let create = try XCTUnwrap(session.apiCalls("createMultitrackProduction").first)
        XCTAssertEqual(create["trackIds"] as? [String], ["Ch_1_BOOM", "Ch_2_LAVMIX", "Ch_3_LAV1"])
        let outputFiles = create["outputFiles"] as? [[String: Any]] ?? []
        XCTAssertEqual(outputFiles.first?["ending"] as? String, "wav.zip")
        XCTAssertEqual(outputFiles.last?["mono_mixdown"] as? Bool, true)
        let tracks = create["trackAlgorithms"] as? [String: [String: Any]] ?? [:]
        XCTAssertEqual(tracks["Ch_1_BOOM"]?["denoise"] as? Bool, true)
        XCTAssertTrue(session.apiCalls("createProduction").isEmpty, "multitrack uses one production per file")

        let upload = try XCTUnwrap(session.apiCalls("upload").first)
        XCTAssertEqual(upload.uploadedFiles.map { $0["name"] as? String }, ["Ch_1_BOOM.wav", "Ch_2_LAVMIX.wav", "Ch_3_LAV1.wav"])
        XCTAssertEqual(upload.uploadedFiles.compactMap { $0["channels"] as? Int }, [1, 1, 1])
        XCTAssertEqual(session.apiCalls("download").count, 2, "tracks archive + mixdown")
    }

    func testMultitrackMasterOnlyWithoutMixdown() throws {
        makeSession(mode: .mixPreparation)
        let original = try session.makeWav("scene4.wav", fourChannelTake(minute: 40))
        session.launch()
        session.addFiles(expectedCount: 1)
        let warning = session.group(1).descendants(matching: .any)["group.unconfigured"]
        XCTAssertTrue(warning.exists)

        // The master algorithms are on by default and count as processing
        session.setProductionMode("Multitrack")
        XCTAssertTrue(warning.waitForNonExistence(timeout: 3), "multitrack defaults make the group processable")

        // All master processing off and no track algorithm: nothing to do
        session.setCard("Master Leveler", on: false)
        session.setCard("Master Loudness Normalization", on: false)
        session.setCheckbox("checkbox.Noise Gate", on: false)
        session.setCheckbox("checkbox.Crosstalk / Mic Bleed Damping", on: false)
        XCTAssertTrue(warning.waitForExistence(timeout: 3))

        // Crosstalk damping alone is enough
        session.setCheckbox("checkbox.Crosstalk / Mic Bleed Damping", on: true)
        XCTAssertTrue(warning.waitForNonExistence(timeout: 3))
        XCTAssertEqual(session.uploadPlan, "1 multitrack production per file — 4 tracks")

        session.processBatch()
        session.waitForBatchToFinish()
        try assertMixPrepOutput(original: original,
                                output: session.outputDirectory.appendingPathComponent("scene4.wav"),
                                channels: Array(repeating: .processed(bits: 16), count: 4))
        let create = try XCTUnwrap(session.apiCalls("createMultitrackProduction").first)
        let master = create["masterAlgorithms"] as? [String: Any] ?? [:]
        XCTAssertEqual(master["crossgate"] as? Bool, true)
        XCTAssertEqual(master["gate"] as? Bool, false)
        XCTAssertEqual(master["leveler"] as? Bool, false)
        XCTAssertEqual(master["normloudness"] as? Bool, false)
        XCTAssertEqual((create["outputFiles"] as? [[String: Any]])?.count, 1, "no mixdown requested")
        XCTAssertEqual(session.apiCalls("download").count, 1)
    }

    func testGroupsRunWithTheirOwnModeAndUnconfiguredGroupsAreSkipped() throws {
        makeSession(mode: .mixPreparation)
        let names = ["BOOM", "LAV1", "LAV2"]
        let a = try session.makeWav("A.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 10, m: 0, s: 0), trackNames: names))
        try session.makeWav("B.wav", WavFixture(channels: 2, seconds: 1, timeReference: WavFixture.timeReference(h: 11, m: 0, s: 0)))
        let c = try session.makeWav("C.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 12, m: 0, s: 0), trackNames: names))
        session.launch()
        session.addFiles(expectedCount: 3)

        // Group 1: singletrack, channel 1 only
        session.selectGroup(1)
        session.setCheckbox("channel.2", on: false)
        session.setCheckbox("channel.3", on: false)
        session.setCard("Adaptive Leveler", on: true)

        // Group 3: multitrack with the noise gate; group 2 stays unconfigured
        session.selectGroup(3)
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("channel.2").stringValue == "on" },
                      "group 3 has its own, untouched channel selection")
        session.setProductionMode("Multitrack")
        session.setCheckbox("checkbox.Crosstalk / Mic Bleed Damping", on: false)

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 2 files processed")
        XCTAssertEqual(session.outputNames, ["A.wav", "C.wav"])
        XCTAssertEqual(session.fileState("B"), "pending")

        try assertMixPrepOutput(original: a, output: session.outputDirectory.appendingPathComponent("A.wav"),
                                channels: [.processed(bits: 24), .untouched, .untouched])
        try assertMixPrepOutput(original: c, output: session.outputDirectory.appendingPathComponent("C.wav"),
                                channels: Array(repeating: .processed(bits: 16), count: 3))
        XCTAssertEqual(session.apiCalls("createProduction").map(\.title), ["A Ch 1"])
        XCTAssertEqual(session.apiCalls("createMultitrackProduction").map(\.title), ["C"])
        let master = session.apiCalls("createMultitrackProduction").first?["masterAlgorithms"] as? [String: Any]
        XCTAssertEqual(master?["gate"] as? Bool, true)
        XCTAssertEqual(master?["crossgate"] as? Bool, false)
    }

    func testSettingsJsonSidecarDescribesTheMultitrackProduction() throws {
        makeSession(mode: .mixPreparation)
        try session.makeWav("scene5.wav", fourChannelTake(minute: 50))
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setProductionMode("Multitrack")
        session.setCard("Filtering", on: true)
        session.setCheckbox("checkbox.Settings JSON", on: true)

        session.processBatch()
        session.waitForBatchToFinish()
        XCTAssertEqual(session.outputNames, ["scene5.json", "scene5.wav"])
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: session.outputDirectory.appendingPathComponent("scene5.json"))) as? [String: Any]
        XCTAssertEqual(json?["mode"] as? String, "multitrack")
        XCTAssertNotNil((json?["tracks"] as? [String: Any])?["Ch_4_LAV2"])
    }

    // MARK: - Real recordings

    /// The untracked sample recordings in Testfiles/: a mono take, a
    /// four-channel and a three-channel MixPre take, all 32-bit float BWF
    func testRealRecordingsAcrossThreeGroups() throws {
        makeSession(mode: .mixPreparation)
        guard let mono = session.copyTestfile("261027_006.WAV"),
              let four = session.copyTestfile("MixPre-082.WAV"),
              let three = session.copyTestfile("MixPre-013.WAV") else {
            throw XCTSkip("Testfiles/ recordings are not available")
        }
        session.launch()
        session.addFiles(expectedCount: 3)

        // Sorted by timecode: 13:14:53 mono, 15:26:55 four-channel, 21:04:36 three-channel
        XCTAssertEqual(groupTimecode(1), "13:14:53")
        XCTAssertEqual(groupSummary(1), "1 ch · 1 file · Singletrack")
        XCTAssertEqual(groupTimecode(2), "15:26:55")
        XCTAssertEqual(groupSummary(2), "4 ch · 1 file · Singletrack")
        XCTAssertEqual(groupTimecode(3), "21:04:36")
        XCTAssertEqual(groupSummary(3), "3 ch · 1 file · Singletrack")

        // Mono: the only channel — the original file goes up as it is
        session.selectGroup(1)
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("channel.1").label == "Ch 1 (Boom)" })
        session.setCard("Adaptive Leveler", on: true)

        // Four channels: lavs only, singletrack
        session.selectGroup(2)
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("channel.4").label == "Ch 4 (LAV2)" })
        session.setCheckbox("channel.1", on: false)
        session.setCheckbox("channel.2", on: false)
        session.setCard("Noise & Reverb Reduction", on: true)

        // Three channels: multitrack, mixdown replaces the LAVMIX channel
        session.selectGroup(3)
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("channel.2").label == "Ch 2 (LAVMIX)" })
        session.setProductionMode("Multitrack")
        session.setCheckbox("channel.2", on: false)
        session.setCard("Adaptive Leveler", on: true)
        session.setCheckbox("checkbox.Also download the master mixdown", on: true)
        session.pick("Ch 2 (LAVMIX)", in: "mixdown.target")

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(timeout: 240), "Status: Done — 3 files processed")

        try assertMixPrepOutput(original: mono, output: session.outputDirectory.appendingPathComponent("261027_006.WAV"),
                                channels: [.processed(bits: 24)])
        try assertMixPrepOutput(original: four, output: session.outputDirectory.appendingPathComponent("MixPre-082.WAV"),
                                channels: [.untouched, .untouched, .processed(bits: 24), .processed(bits: 24)])
        try assertMixPrepOutput(original: three, output: session.outputDirectory.appendingPathComponent("MixPre-013.WAV"),
                                channels: [.processed(bits: 16), .mixdown(of: [0, 2], bits: 24), .processed(bits: 16)])

        let uploads = session.apiCalls("upload").flatMap(\.uploadedFiles)
        XCTAssertTrue(uploads.contains { $0["name"] as? String == "261027_006.WAV" },
                      "a job covering the whole mono file uploads the original")
        XCTAssertEqual(session.apiCalls("createProduction").map(\.title).sorted(),
                       ["261027_006 Ch 1", "MixPre-082 Ch 3", "MixPre-082 Ch 4"])
        XCTAssertEqual(session.apiCalls("createMultitrackProduction").first?["trackIds"] as? [String],
                       ["Ch_1_BOOM", "Ch_3_LAV1"])
    }

    // MARK: - Helpers

    private func groupTimecode(_ index: Int) -> String {
        session.group(index).descendants(matching: .any)["group.timecode"].firstMatch.stringValue
    }

    private func groupSummary(_ index: Int) -> String {
        session.group(index).descendants(matching: .any)["group.summary"].firstMatch.label
    }

    private func writeAiff(named name: String) throws {
        let url = session.inputDirectory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        try file.write(from: buffer)
    }
}
