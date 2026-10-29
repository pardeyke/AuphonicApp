import XCTest
import AVFoundation

/// Standard mode: whole files go up, processed files come back in the chosen
/// format and land in the destination folder under their original names.
final class StandardModeUITests: AppUITestCase {

    func testEmptyStateAndNothingConfiguredAlert() throws {
        makeSession()
        _ = try makeStereoTakes(2)
        session.launch()

        XCTAssertTrue(session.element("sidebar.dropZone").exists, "drop zone shows before files are added")
        XCTAssertFalse(session.element("toolbar.processBatch").isEnabled, "nothing to process yet")
        XCTAssertEqual(session.element("credits.total").stringValue, "Credits: 10:00:00")

        session.addFiles(expectedCount: 2)
        XCTAssertEqual(Set(session.rowNames), ["take_01", "take_02"])
        XCTAssertEqual(session.fileState("take_01"), "pending")
        XCTAssertTrue(session.fileStatusText("take_01").contains("2ch · 24bit"), session.fileStatusText("take_01"))

        // Keep Format and no algorithm: nothing worth a production
        XCTAssertFalse(session.element("toolbar.testSettings").isEnabled)
        session.element("toolbar.processBatch").click()
        session.dismissAlert(containing: "Select a preset, enable a processing option or choose an output format")
        XCTAssertTrue(session.apiCalls("createProduction").isEmpty)
    }

    func testProcessBatchAsWav24WithLeveler() throws {
        makeSession()
        let originals = try makeStereoTakes(2)
        session.launch()
        session.addFiles(expectedCount: 2)

        session.setCard("Adaptive Leveler", on: true)
        session.pick("WAV 24-bit", in: "picker.Format", card: "Output File")
        XCTAssertEqual(session.uploadPlan, "2 productions — one per file, returned as WAV 24-bit")
        XCTAssertEqual(session.element("credits.cost").stringValue, "Cost: 6:00", "two files at the 3-minute minimum")
        XCTAssertTrue(session.element("credits.productions").stringValue.hasPrefix("2 productions"))

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 2 files processed")
        XCTAssertEqual(session.fileState("take_01"), "done")
        XCTAssertEqual(session.fileState("take_02"), "done")
        XCTAssertTrue(session.element("status.showInFinder").exists)

        XCTAssertEqual(session.outputNames, ["take_01.wav", "take_02.wav"])
        for original in originals {
            let output = try WavFile(url: session.outputDirectory.appendingPathComponent(original.lastPathComponent))
            XCTAssertEqual(output.bitsPerSample, 24)
            XCTAssertEqual(output.channels, 2)
            let source = try WavFile(url: original)
            XCTAssertEqual(output.frameCount, source.frameCount)
            for channel in 0..<2 {
                let expected = source.samples(channel: channel).map { $0 * simulatedGain }
                let actual = output.samples(channel: channel)
                let error = zip(expected, actual).map { abs($0 - $1) }.max() ?? .infinity
                XCTAssertLessThan(error, 3e-7, "channel \(channel + 1) of \(original.lastPathComponent)")
            }
        }

        // The whole file goes up untouched, once per file
        let creates = session.apiCalls("createProduction")
        XCTAssertEqual(creates.map(\.title).sorted(), ["take_01", "take_02"])
        for create in creates {
            XCTAssertEqual(create.algorithms["leveler"] as? Bool, true)
            XCTAssertEqual(create.outputFormat, "wav-24bit")
            XCTAssertEqual(create["preset"] as? String, "")
        }
        let uploads = session.apiCalls("upload").flatMap(\.uploadedFiles)
        XCTAssertEqual(uploads.map { $0["name"] as? String }.compactMap { $0 }.sorted(), ["take_01.wav", "take_02.wav"])
        XCTAssertEqual(uploads.compactMap { $0["channels"] as? Int }, [2, 2])
        XCTAssertTrue(session.apiCalls("delete").isEmpty, "housekeeping is off by default")
    }

    func testEveryOutputFormatComesBackWithItsExtension() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Loudness Normalization", on: true)

        let formats: [(menu: String, api: String, ext: String, bitrate: String?)] = [
            ("WAV 16-bit", "wav-16bit", "wav", nil),
            ("FLAC", "flac", "flac", nil),
            ("ALAC", "alac", "m4a", nil),
            // MP3's default 112 kbps carries over: every later format offers it
            ("MP3 (CBR)", "mp3", "mp3", "112 kbps"),
            ("MP3 (VBR)", "mp3-vbr", "mp3", "112 kbps"),
            ("AAC", "aac", "aac", "112 kbps"),
            ("OGG Vorbis", "vorbis", "ogg", "112 kbps"),
            ("Opus", "opus", "opus", "112 kbps")
        ]

        for (index, format) in formats.enumerated() {
            session.pick(format.menu, in: "picker.Format", card: "Output File")
            let bitrate = session.card("Output File").descendants(matching: .popUpButton)["picker.Bitrate"]
            if let expected = format.bitrate {
                XCTAssertTrue(bitrate.waitForExistence(timeout: 3), "\(format.menu) offers a bitrate")
                XCTAssertEqual(bitrate.stringValue, expected, "bitrate shown for \(format.menu)")
            } else {
                XCTAssertFalse(bitrate.exists, "\(format.menu) has no bitrate")
            }

            let target = session.outputDirectory.appendingPathComponent("run\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            session.selectFile("take_01")
            session.processSelected(into: target)
            XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 file processed", format.menu)

            let written = try FileManager.default.contentsOfDirectory(atPath: target.path)
            XCTAssertEqual(written, ["take_01.\(format.ext)"], format.menu)
            XCTAssertEqual(session.apiCalls("createProduction").last?.outputFormat, format.api)
        }

        // Real encoders behind the lossless formats: the files decode as audio
        for (index, ext) in [(0, "wav"), (1, "flac"), (2, "m4a")] {
            let url = session.outputDirectory.appendingPathComponent("run\(index)/take_01.\(ext)")
            let decoded = try AVAudioFile(forReading: url)
            XCTAssertEqual(decoded.fileFormat.channelCount, 2, ext)
            XCTAssertEqual(Double(decoded.length), 2 * 48_000, accuracy: 4096, ext)
        }
    }

    func testBitrateChoiceIsSent() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)

        session.pick("MP3 (CBR)", in: "picker.Format", card: "Output File")
        session.pick("320 kbps", in: "picker.Bitrate", card: "Output File")
        session.processBatch()
        session.waitForBatchToFinish()

        let outputFiles = session.apiCalls("createProduction").first?.settings["output_files"] as? [[String: Any]]
        XCTAssertEqual(outputFiles?.first?["bitrate"] as? String, "320")
        XCTAssertEqual(session.outputNames, ["take_01.mp3"])

        // Opus tops out at 256 kbps, so the bitrate falls back to its default
        session.pick("Opus", in: "picker.Format", card: "Output File")
        XCTAssertEqual(session.card("Output File").descendants(matching: .popUpButton)["picker.Bitrate"].stringValue, "48 kbps")
    }

    func testKeepFormatReturnsTheSourceFormat() throws {
        makeSession()
        _ = try makeStereoTakes(1, format: .int16)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Filtering", on: true)
        XCTAssertEqual(session.uploadPlan, "1 production — one per file, returned as the input format")

        session.processBatch()
        session.waitForBatchToFinish()
        XCTAssertEqual(session.apiCalls("createProduction").first?.outputFormat, "wav-16bit",
                       "Keep Format resolves a 16-bit WAV to Auphonic's 16-bit WAV")
        XCTAssertEqual(try WavFile(url: session.outputDirectory.appendingPathComponent("take_01.wav")).bitsPerSample, 16)
    }

    func testPresetDrivesTheProductionUntilASettingChanges() throws {
        makeSession()
        _ = try makeStereoTakes(2)
        session.launch()
        session.addFiles(expectedCount: 2)

        session.pick("UITest Dialog", in: "preset.picker")
        // The preset's algorithms show up in the cards
        let leveler = session.card("Adaptive Leveler").descendants(matching: .any)["card.toggle"].firstMatch
        XCTAssertTrue(session.waitUntil(timeout: 5) { leveler.isOn }, "preset switched the leveler on")
        XCTAssertTrue(session.card("Loudness Normalization").descendants(matching: .any)["card.toggle"].firstMatch.isOn)
        XCTAssertEqual(session.apiCalls("fetchPresetDetails").last?["uuid"] as? String, "preset-dialog")

        session.selectFile("take_01")
        session.processSelected()
        session.waitForBatchToFinish()
        XCTAssertEqual(session.apiCalls("createProduction").last?["preset"] as? String, "preset-dialog")

        // Any edit makes the manual settings authoritative
        session.setCard("Filtering", on: false)
        session.selectFile("take_02")
        session.processSelected()
        session.waitForBatchToFinish()
        let modified = try XCTUnwrap(session.apiCalls("createProduction").last)
        XCTAssertEqual(modified["preset"] as? String, "")
        XCTAssertEqual(modified.algorithms["filtering"] as? Bool, false)
        XCTAssertEqual(modified.algorithms["leveler"] as? Bool, true)
        XCTAssertEqual(modified.algorithms["loudnesstarget"] as? Int, -23)
    }

    func testStorePresetSavesTheCurrentSettings() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Noise & Reverb Reduction", on: true)

        session.element("preset.store").click()
        // The alert's text field (SwiftUI drops identifiers on alert fields)
        let name = app.windows.descendants(matching: .textField).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Save Preset alert with a name field")
        name.click()
        name.typeText("My Interview Preset")
        app.windows.descendants(matching: .button)["Save"].firstMatch.click()

        XCTAssertTrue(session.waitUntil(timeout: 5) { !self.session.apiCalls("savePreset").isEmpty })
        let saved = try XCTUnwrap(session.apiCalls("savePreset").first)
        XCTAssertEqual(saved["name"] as? String, "My Interview Preset")
        XCTAssertEqual(saved.algorithms["denoise"] as? Bool, true)

        let picker = session.element("preset.picker")
        XCTAssertTrue(session.waitUntil(timeout: 5) { picker.stringValue == "My Interview Preset" },
                      "the stored preset becomes the selected one")
    }

    func testSettingsJsonSidecarIsWrittenNextToTheOutput() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Adaptive Leveler", on: true)
        session.setCheckbox("checkbox.Settings JSON", on: true)

        session.processBatch()
        session.waitForBatchToFinish()
        XCTAssertEqual(session.outputNames, ["take_01.json", "take_01.wav"])
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: session.outputDirectory.appendingPathComponent("take_01.json"))) as? [String: Any]
        XCTAssertEqual((json?["algorithms"] as? [String: Any])?["leveler"] as? Bool, true)
        XCTAssertNotNil(json?["preset"])
    }

    func testTestSettingsUploadsAtMostThreeMinutesAndLoadsTheProcessedLane() throws {
        makeSession()
        // Long take at a low rate keeps the fixture small: 200 s mono
        try session.makeWav("long_take.wav", WavFixture(channels: 1, sampleRate: 8_000, format: .int24, seconds: 200))
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Adaptive Leveler", on: true)

        XCTAssertFalse(session.element("player.slot").exists, "no A/B before a test run")
        let testButton = session.element("toolbar.testSettings")
        XCTAssertTrue(testButton.isEnabled)
        testButton.click()

        XCTAssertTrue(session.element("player.slot").waitForExistence(timeout: 30), "processed lane appears for A/B")
        XCTAssertEqual(app.tabGroups["player.slot"].tabs.count, 2)
        session.waitForBatchToFinish()

        let upload = try XCTUnwrap(session.apiCalls("upload").first?.uploadedFiles.first)
        XCTAssertEqual(upload["frames"] as? Int, 180 * 8_000, "the test drive never uploads more than 3 minutes")
        XCTAssertTrue(session.outputFiles.isEmpty, "a test drive writes nothing into a destination")
        XCTAssertEqual(session.fileState("long_take"), "pending", "the test output does not mark the take as done")
    }

    func testCancelStopsTheBatchAndLeavesNoOutput() throws {
        makeSession(scenario: "neverFinishes")
        _ = try makeStereoTakes(2)
        session.launch()
        session.addFiles(expectedCount: 2)
        session.setCard("Adaptive Leveler", on: true)

        session.processBatch()
        let cancel = session.element("toolbar.cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertTrue(session.waitUntil(timeout: 10) { self.session.fileState("take_01") == "processing" })
        XCTAssertFalse(app.tabGroups["toolbar.mode"].isEnabled, "the mode can't change while a batch runs")
        XCTAssertFalse(session.element("sidebar.addFiles").isEnabled)

        cancel.click()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Cancelled after 0 of 2 files")
        XCTAssertEqual(session.fileState("take_01"), "pending")
        XCTAssertEqual(session.fileState("take_02"), "pending")
        XCTAssertTrue(session.outputFiles.isEmpty)
        XCTAssertEqual(session.apiCalls("createProduction").count, 1, "the second file never started")
    }

    func testCancellingTheDestinationPanelStartsNothing() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Adaptive Leveler", on: true)

        session.element("toolbar.processBatch").click()
        session.cancelPanel()
        XCTAssertEqual(session.statusText, "Status: Ready")
        XCTAssertTrue(session.apiCalls("createProduction").isEmpty)
    }

    func testOutputNamesNeverOverwrite() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.pick("WAV 24-bit", in: "picker.Format", card: "Output File")

        session.processBatch()
        session.waitForBatchToFinish()
        session.processBatch()
        session.waitForBatchToFinish()
        XCTAssertEqual(session.outputNames, ["take_01.wav", "take_01_2.wav"])
    }

    func testRemoveAndClearFiles() throws {
        makeSession()
        _ = try makeStereoTakes(3)
        session.launch()
        session.addFiles(expectedCount: 3)

        session.fileRow("take_02").descendants(matching: .any)["file.remove"].firstMatch.click()
        XCTAssertTrue(session.waitUntil(timeout: 5) { self.session.element("sidebar.fileCount").stringValue == "2 files" })
        XCTAssertEqual(Set(session.rowNames), ["take_01", "take_03"])

        // Adding the same folder again only brings back the removed take
        session.addFiles(expectedCount: 3)

        session.element("sidebar.clear").click()
        XCTAssertTrue(session.element("sidebar.dropZone").waitForExistence(timeout: 5))
        XCTAssertTrue(session.rowNames.isEmpty)
    }

    func testUnreadableFilesAreSkippedWithAMessage() throws {
        makeSession()
        _ = try makeStereoTakes(1)
        try Data("not really audio".utf8).write(to: session.inputDirectory.appendingPathComponent("broken.wav"))
        session.launch()

        session.element("sidebar.addFiles").click()
        session.choose(session.inputDirectory)
        session.dismissAlert(containing: "1 file(s) could not be read and were skipped.")
        XCTAssertEqual(session.rowNames, ["take_01"])
    }

    func testRealRecordingAsWav16() throws {
        makeSession()
        guard let original = session.copyTestfile("261027_006.WAV") else {
            throw XCTSkip("Testfiles/261027_006.WAV is not available")
        }
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Adaptive Leveler", on: true)
        session.pick("WAV 16-bit", in: "picker.Format", card: "Output File")

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(timeout: 120), "Status: Done — 1 file processed")

        let source = try WavFile(url: original)
        let output = try WavFile(url: session.outputDirectory.appendingPathComponent("261027_006.wav"))
        XCTAssertEqual(output.bitsPerSample, 16)
        XCTAssertEqual(output.channels, 1)
        XCTAssertEqual(output.frameCount, source.frameCount)
        let upload = try XCTUnwrap(session.apiCalls("upload").first?.uploadedFiles.first)
        XCTAssertEqual(upload["name"] as? String, "261027_006.WAV", "Standard mode uploads the original file")
        XCTAssertEqual(upload["isFloat"] as? Bool, true)
    }
}
