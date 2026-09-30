import XCTest

final class CurrentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarAndFocusPreserveNarrowWindow() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("current-launch-test-\(UUID().uuidString)", isDirectory: true)
        let configRoot = fixture.appendingPathComponent("config", isDirectory: true)
        let configDirectory = configRoot.appendingPathComponent("current", isDirectory: true)
        let library = fixture.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try "library-root = \(library.path)\n".write(
            to: configDirectory.appendingPathComponent("config.current"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchEnvironment["XDG_CONFIG_HOME"] = configRoot.path
        app.launchArguments += ["-workspace.sidebarVisible", "YES", "-workspace.focusMode", "NO"]
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: fixture)
        }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let isolatedLibrary = NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: library.appendingPathComponent(".current-library.json").path)
        }
        expectation(for: isolatedLibrary, evaluatedWith: nil)
        waitForExpectations(timeout: 5)

        let window = app.windows.firstMatch
        let sidebar = app.descendants(matching: .any).matching(identifier: "workspace.sidebar").firstMatch
        let leaveFocus = app.buttons.matching(identifier: "workspace.leaveFocus").firstMatch
        let sidebarIsVisible = { sidebar.exists && sidebar.isHittable }
        let focusIsVisible = { leaveFocus.exists && leaveFocus.isHittable }
        waitForStableState("The workspace should launch with its sidebar visible") {
            sidebarIsVisible() && !focusIsVisible()
        }

        // Exercise the real WindowGroup and native resize path. A test that starts
        // wider than the regression threshold could hide the 820 → 1040 growth.
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 818, dy: 638))
        corner.click(forDuration: 0.1, thenDragTo: target)
        waitForStableState("Native resize must reach 820 × 640 before testing sidebar restoration") {
            abs(window.frame.width - 820) <= 3 && abs(window.frame.height - 640) <= 3
        }
        let originalFrame = window.frame
        XCTAssertEqual(originalFrame.width, 820, accuracy: 3)
        XCTAssertEqual(originalFrame.height, 640, accuracy: 3)

        func requireWorkspace(sidebar visible: Bool, focus: Bool, after action: String) {
            waitForStableState("\(action) should preserve window bounds and the expected sidebar/focus state") {
                sidebarIsVisible() == visible && focusIsVisible() == focus
                    && abs(window.frame.minX - originalFrame.minX) <= 2
                    && abs(window.frame.minY - originalFrame.minY) <= 2
                    && abs(window.frame.width - originalFrame.width) <= 2
                    && abs(window.frame.height - originalFrame.height) <= 2
            }
            XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 2, action)
            XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 2, action)
        }

        for _ in 0..<2 {
            app.typeKey("\\", modifierFlags: .command)
            requireWorkspace(sidebar: false, focus: false, after: "Hide Sidebar")
            app.typeKey("\\", modifierFlags: .command)
            requireWorkspace(sidebar: true, focus: false, after: "Show Sidebar")
        }

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        requireWorkspace(sidebar: false, focus: true, after: "Enter Focus Mode with sidebar shown")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        requireWorkspace(sidebar: true, focus: false, after: "Leave Focus Mode with sidebar shown")

        app.typeKey("\\", modifierFlags: .command)
        requireWorkspace(sidebar: false, focus: false, after: "Hide Sidebar before Focus Mode")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        requireWorkspace(sidebar: false, focus: true, after: "Enter Focus Mode with sidebar hidden")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [.command, .shift])
        requireWorkspace(sidebar: false, focus: false, after: "Leave Focus Mode with sidebar hidden")
        app.typeKey("\\", modifierFlags: .command)
        requireWorkspace(sidebar: true, focus: false, after: "Restore Sidebar after Focus Mode")
    }

    @MainActor
    private func waitForStableState(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) {
        var matchingSince: Date?
        let predicate = NSPredicate { _, _ in
            guard condition() else {
                matchingSince = nil
                return false
            }
            if let matchingSince {
                // Require the desired state to outlast a native disclosure animation.
                return Date().timeIntervalSince(matchingSince) >= 0.4
            }
            matchingSince = Date()
            return false
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            description, file: file, line: line)
    }
}
