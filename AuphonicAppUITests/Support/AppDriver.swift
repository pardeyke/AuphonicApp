import XCTest

/// High-level actions on the running app, phrased the way a user works:
/// add files, pick a mode, switch a card on, process, read the status.
@MainActor
extension AppSession {

    // MARK: - Elements

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func fileRow(_ name: String) -> XCUIElement {
        element("file.\(name)")
    }

    /// Clicks a file row. Rows are containers, which XCUITest does not
    /// consider hittable inside the grouped list, so click their centre.
    func selectFile(_ name: String) {
        let row = fileRow(name)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row \(name)")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).click()
    }

    /// Clicks a group bubble (selects the group for configuration)
    func selectGroup(_ index: Int) {
        let header = group(index)
        XCTAssertTrue(header.waitForExistence(timeout: 5), "no group \(index)")
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    /// pending / processing / done / failed
    func fileState(_ name: String) -> String {
        fileRow(name).descendants(matching: .any)["file.state"].firstMatch.label
    }

    func fileStatusText(_ name: String) -> String {
        fileRow(name).descendants(matching: .any)["file.status"].firstMatch.stringValue
    }

    func group(_ index: Int) -> XCUIElement {
        element("group.\(index)")
    }

    func card(_ title: String) -> XCUIElement {
        element("card.\(title)")
    }

    var statusText: String { element("status.text").stringValue }

    var uploadPlan: String { element("uploadPlan").stringValue }

    var rowNames: [String] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'file.' AND NOT identifier IN {'file.state', 'file.status', 'file.remove'}"))
            .allElementsBoundByIndex
            .map { String($0.identifier.dropFirst("file.".count)) }
    }

    // MARK: - Open panel

    /// Drives the system open panel: go to `url` (Cmd+Shift+G) and confirm.
    /// Confirming without a selection picks the folder being shown, which
    /// is how both the Add Files panel and the destination panel take a folder.
    func choose(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let panel = app.dialogs["open-panel"]
        guard panel.waitForExistence(timeout: 10) else {
            XCTFail("open panel did not appear", file: file, line: line)
            return
        }
        app.activate()
        panel.typeKey("g", modifierFlags: [.command, .shift])
        let goTo = panel.descendants(matching: .textField).firstMatch
        if goTo.waitForExistence(timeout: 5) {
            goTo.typeText(url.path + "\n")
        } else {
            panel.typeText(url.path + "\n")
        }

        // Wait until the panel shows the folder before confirming
        let confirm = panel.buttons["OKButton"]
        _ = confirm.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 0.8)
        confirm.click()
        if !panel.waitForNonExistence(timeout: 8) {
            // The first click can land while the panel is still navigating
            if confirm.exists { confirm.click() }
            if !panel.waitForNonExistence(timeout: 8) {
                XCTFail("open panel did not close", file: file, line: line)
            }
        }
    }

    /// App menu ▸ Settings… (the Settings scene)
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        app.menuBarItems["AuphonicApp"].click()
        let item = app.menuBarItems["AuphonicApp"].menuItems["Settings…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "no Settings menu item", file: file, line: line)
        item.click()
    }

    func closeSettings() {
        app.typeKey("w", modifierFlags: .command)
    }

    func cancelPanel(file: StaticString = #filePath, line: UInt = #line) {
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "open panel did not appear", file: file, line: line)
        panel.buttons["CancelButton"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    /// Add Files → pick a folder (the app expands it to the audio files inside)
    func addFiles(from directory: URL? = nil, expectedCount: Int? = nil,
                  file: StaticString = #filePath, line: UInt = #line) {
        let addButton = element("sidebar.addFiles")
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), file: file, line: line)
        addButton.click()
        choose(directory ?? inputDirectory, file: file, line: line)

        if let expectedCount {
            let label = "\(expectedCount) file\(expectedCount == 1 ? "" : "s")"
            let count = element("sidebar.fileCount")
            let matched = waitUntil(timeout: 15) { count.exists && count.stringValue == label }
            XCTAssertTrue(matched, "expected \(label), sidebar shows '\(count.exists ? count.stringValue : "nothing")'",
                          file: file, line: line)
        }
    }

    // MARK: - Toolbar

    func switchMode(to mode: Mode, file: StaticString = #filePath, line: UInt = #line) {
        let title = mode == .standard ? "Standard" : "Mix Preparation"
        let tab = app.tabGroups["toolbar.mode"].tabs[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        tab.click()
    }

    /// Process Batch, then pick the session's output folder in the panel
    func processBatch(into directory: URL? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let button = element("toolbar.processBatch")
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.click()
        choose(directory ?? outputDirectory, file: file, line: line)
    }

    /// Process (the selected take only)
    func processSelected(into directory: URL? = nil, file: StaticString = #filePath, line: UInt = #line) {
        element("toolbar.process").click()
        choose(directory ?? outputDirectory, file: file, line: line)
    }

    /// Waits for the batch to end and returns the final status line
    @discardableResult
    func waitForBatchToFinish(timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) -> String {
        let finished = waitUntil(timeout: timeout) {
            let text = self.statusText
            return text.hasPrefix("Status: Done") || text.hasPrefix("Status: Cancelled")
        }
        XCTAssertTrue(finished, "batch did not finish; status: \(statusText)", file: file, line: line)
        // The toolbar swaps Cancel back for the process buttons when the run ends
        _ = element("toolbar.processBatch").waitForExistence(timeout: 5)
        return statusText
    }

    // MARK: - Settings controls

    /// Switches an algorithm card on or off
    func setCard(_ title: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = card(title).descendants(matching: .any)["card.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no card '\(title)'", file: file, line: line)
        if toggle.isOn != on { toggle.click() }
        XCTAssertTrue(waitUntil(timeout: 3) { toggle.isOn == on }, "card '\(title)' did not switch", file: file, line: line)
    }

    /// Picks `option` in a pop-up button, optionally inside a card
    func pick(_ option: String, in pickerID: String, card cardTitle: String? = nil,
              file: StaticString = #filePath, line: UInt = #line) {
        let scope = cardTitle.map { card($0) } ?? app
        let popUp = scope.descendants(matching: .popUpButton)[pickerID].firstMatch
        XCTAssertTrue(popUp.waitForExistence(timeout: 5), "no picker \(pickerID)", file: file, line: line)
        popUp.click()
        let item = app.menuItems[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no menu item '\(option)'", file: file, line: line)
        item.click()
        XCTAssertTrue(waitUntil(timeout: 3) { popUp.stringValue == option },
                      "\(pickerID) shows '\(popUp.stringValue)' instead of '\(option)'", file: file, line: line)
    }

    /// Glass checkbox (channel pills, option chips)
    func setCheckbox(_ identifier: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let box = element(identifier)
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no checkbox \(identifier)", file: file, line: line)
        if (box.stringValue == "on") != on { box.click() }
        XCTAssertTrue(waitUntil(timeout: 3) { (box.stringValue == "on") == on }, file: file, line: line)
    }

    func setProductionMode(_ title: String) {
        app.tabGroups["group.productionMode"].tabs[title].click()
    }

    // MARK: - Alerts

    /// Waits for an alert containing `text`, returns its message, clicks `button`
    @discardableResult
    func dismissAlert(containing text: String, button: String = "OK",
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        let message = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
        guard message.waitForExistence(timeout: 10) else {
            XCTFail("no alert containing '\(text)'", file: file, line: line)
            return ""
        }
        let value = message.stringValue
        // Scoped to windows: the Touch Bar mirrors alert buttons
        let dismiss = app.windows.descendants(matching: .button)[button].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3), "alert has no '\(button)' button", file: file, line: line)
        dismiss.click()
        _ = message.waitForNonExistence(timeout: 5)
        return value
    }

    // MARK: - Waiting

    func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}

extension XCUIElement {
    var stringValue: String { (value as? String) ?? "" }

    /// Switch/checkbox state
    var isOn: Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return string == "1" || string == "on" }
        return false
    }
}
