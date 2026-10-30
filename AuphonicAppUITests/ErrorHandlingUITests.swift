import XCTest

/// What the user sees when Auphonic (or the connection) misbehaves, and the
/// Settings window paths: missing token, housekeeping.
final class ErrorHandlingUITests: AppUITestCase {

    func testProcessingErrorFailsEveryFileWithAuphonicsMessage() throws {
        makeSession(scenario: "processingError")
        _ = try makeStereoTakes(2)
        session.launch()
        session.addFiles(expectedCount: 2)
        session.setCard("Adaptive Leveler", on: true)

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 2 of 2 files failed")
        for name in ["take_01", "take_02"] {
            XCTAssertEqual(session.fileState(name), "failed")
            XCTAssertEqual(session.fileStatusText(name), "\(name).wav: Simulated processing failure")
        }
        XCTAssertTrue(session.outputFiles.isEmpty)
        XCTAssertTrue(session.apiCalls("download").isEmpty)
    }

    func testOneFailingTakeDoesNotStopTheBatch() throws {
        makeSession(mode: .mixPreparation, scenario: "failTitle=take_02")
        let takes = try makeStereoTakes(3)
        session.launch()
        session.addFiles(expectedCount: 3)
        session.setCard("Adaptive Leveler", on: true)

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 of 3 files failed")
        XCTAssertEqual(session.fileState("take_01"), "done")
        XCTAssertEqual(session.fileState("take_02"), "failed")
        XCTAssertTrue(session.fileStatusText("take_02").contains("Simulated processing failure"))
        XCTAssertEqual(session.fileState("take_03"), "done")
        XCTAssertEqual(session.outputNames, ["take_01.wav", "take_03.wav"], "a failed take leaves no partial output")
        try assertMixPrepOutput(original: takes[2], output: session.outputDirectory.appendingPathComponent("take_03.wav"),
                                channels: [.processed(bits: 24), .processed(bits: 24)])
    }

    func testRevokedTokenFailsRightAway() throws {
        makeSession(scenario: "revokedToken")
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Filtering", on: true)

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(timeout: 15), "Status: Done — 1 of 1 files failed")
        XCTAssertEqual(session.fileStatusText("take_01"), "Invalid API token")
        let polls = session.apiCalls("status")
        XCTAssertEqual(polls.count, 1, "a rejected token is not retried")
    }

    func testTransientPollErrorsAreRetried() throws {
        makeSession(scenario: "transientErrors=4")
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setCard("Filtering", on: true)

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 file processed")
        XCTAssertEqual(session.apiCalls("status").filter { $0["result"] as? String == "timeout" }.count, 4)
        XCTAssertEqual(session.outputNames, ["take_01.wav"])
    }

    func testRejectedProductionFailsTheFile() throws {
        makeSession(mode: .mixPreparation, scenario: "createFails")
        _ = try makeStereoTakes(1)
        session.launch()
        session.addFiles(expectedCount: 1)
        session.setProductionMode("Multitrack")

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 of 1 files failed")
        XCTAssertEqual(session.fileStatusText("take_01"), "Simulated: production rejected")
        XCTAssertTrue(session.apiCalls("upload").isEmpty)
        XCTAssertTrue(session.outputFiles.isEmpty)
    }

    func testConnectionFailureShowsAnAlertAtLaunch() throws {
        makeSession(scenario: "connectionFails")
        session.launch()
        session.dismissAlert(containing: "Connection failed: Simulated connection failure")
        XCTAssertFalse(session.element("credits.total").exists, "no credits without a connection")
    }

    func testMissingTokenLeadsToSettingsAndConnectsOnceEntered() throws {
        makeSession(token: nil)
        _ = try makeStereoTakes(1)
        session.launch()
        XCTAssertFalse(session.element("credits.total").exists, "nothing to show without a token")
        XCTAssertTrue(session.apiCalls("fetchUserInfo").isEmpty)

        session.addFiles(expectedCount: 1)
        session.setCard("Adaptive Leveler", on: true)
        session.element("toolbar.processBatch").click()
        session.dismissAlert(containing: "Add your Auphonic API token", button: "Open Settings…")

        let tokenField = app.descendants(matching: .secureTextField)["settings.token"].firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5), "Settings window opens")
        tokenField.click()
        tokenField.typeText("fresh-token\n")

        // A file with the leveler on has a cost, so the bar shows the remaining credits
        XCTAssertTrue(session.element("credits.remaining").waitForExistence(timeout: 10), "connects once a token is entered")
        XCTAssertEqual(session.apiCalls("fetchUserInfo").count, 1)
        XCTAssertEqual(session.apiCalls("fetchPresets").count, 1)

        // Close Settings and process with the new token
        app.typeKey("w", modifierFlags: .command)
        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 file processed")
    }

    func testHousekeepingDeletesOnlySuccessfulProductions() throws {
        makeSession(mode: .mixPreparation, scenario: "failTitle=take_02")
        _ = try makeStereoTakes(2)
        session.launch()
        session.addFiles(expectedCount: 2)
        session.setCheckbox("channel.2", on: false)
        session.setCard("Adaptive Leveler", on: true)

        // App menu ▸ Settings…: switch housekeeping on
        session.openSettings()
        let housekeeping = app.switches["settings.deleteAfterDownload"].firstMatch
        XCTAssertTrue(housekeeping.waitForExistence(timeout: 5))
        XCTAssertFalse(housekeeping.isOn)
        // The switch flips (the delete calls below prove it) but its
        // accessibility value keeps reporting 0, so the API log is the check
        housekeeping.click()
        Thread.sleep(forTimeInterval: 0.5)
        session.closeSettings()

        session.processBatch()
        XCTAssertEqual(session.waitForBatchToFinish(), "Status: Done — 1 of 2 files failed")

        let created = session.apiCalls("createProduction")
        let succeeded = created.first { $0.title == "take_01 Ch 1" }?["uuid"] as? String
        let failed = created.first { $0.title == "take_02 Ch 1" }?["uuid"] as? String
        let deleted = session.apiCalls("delete").compactMap { $0["uuid"] as? String }
        XCTAssertEqual(deleted, [try XCTUnwrap(succeeded)], "the failed take keeps its production for inspection")
        XCTAssertFalse(deleted.contains(try XCTUnwrap(failed)))
    }

    func testTestSettingsInMixPreparationUsesTheSelectedGroup() throws {
        makeSession(mode: .mixPreparation)
        try session.makeWav("A.wav", WavFixture(channels: 3, seconds: 1, timeReference: WavFixture.timeReference(h: 10, m: 0, s: 0)))
        try session.makeWav("B.wav", WavFixture(channels: 2, seconds: 1, timeReference: WavFixture.timeReference(h: 11, m: 0, s: 0)))
        session.launch()
        session.addFiles(expectedCount: 2)

        XCTAssertFalse(session.element("toolbar.testSettings").isEnabled, "nothing configured")
        session.selectGroup(2)
        session.setCheckbox("channel.1", on: false)
        session.setCard("Noise & Reverb Reduction", on: true)
        XCTAssertTrue(session.waitUntil(timeout: 3) { self.session.element("toolbar.testSettings").isEnabled })

        session.element("toolbar.testSettings").click()
        XCTAssertTrue(session.element("player.slot").waitForExistence(timeout: 20))
        session.waitForBatchToFinish()
        XCTAssertEqual(session.apiCalls("createProduction").map(\.title), ["B Ch 2"])
        XCTAssertTrue(session.outputFiles.isEmpty)
        XCTAssertEqual(session.fileState("B"), "pending")
    }
}
