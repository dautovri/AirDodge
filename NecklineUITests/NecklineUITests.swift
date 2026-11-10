import StoreKitTest
import XCTest

/// Walks every screen with faked head tracking and attaches a screenshot of
/// each. CI exports the attachments so the UI can be reviewed without a device.
@MainActor
final class NecklineUITests: XCTestCase {
    private var storeSession: SKTestSession?

    override func setUp() async throws {
        continueAfterFailure = false
        // Local products so the paywall has plans to show. Best effort: the
        // walkthrough still runs if the session can't be created.
        storeSession = try? SKTestSession(configurationFileNamed: "Neckline")
        storeSession?.disableDialogs = true
        storeSession?.clearTransactions()
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ABFakeMotion", "-NLResetState", "-AppleLanguages", "(en)"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Any element whose label contains `text`. SwiftUI merges row contents
    /// into one element, so exact static-text lookups are brittle.
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(name)")
        tab.tap()
    }

    func testOnboardingEndsOnPaywall() {
        let app = launch([])
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        shot("01-onboarding")
        for _ in 0..<3 { next.tap() }
        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        shot("02-onboarding-disclaimer")
        start.tap()
        XCTAssertTrue(element(app, containing: "Unlimited posture sessions").waitForExistence(timeout: 15))
        sleep(3)   // let the store plans load
        shot("03-paywall")
    }

    func testFreeWalkthrough() {
        let app = launch(["-NLSkipOnboarding"])

        // Today
        let startSession = app.buttons["Start 10-minute session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 20))
        shot("10-today")

        // Posture session
        startSession.tap()
        let end = app.buttons["End session"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        sleep(2)
        shot("11-session-live")
        end.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        shot("12-session-summary")
        done.tap()

        // Routines: play the free routine by skipping through its steps
        tapTab(app, "Routines")
        XCTAssertTrue(element(app, containing: "Morning Mobility").waitForExistence(timeout: 10))
        shot("20-routines")
        element(app, containing: "Desk Reset").tap()
        let skip = app.buttons["Skip this stretch"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        shot("21-routine-player")
        for _ in 0..<Self.deskResetSteps {
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
        }
        XCTAssertTrue(element(app, containing: "Routine complete").waitForExistence(timeout: 10))
        shot("22-routine-complete")
        app.buttons["Done"].tap()

        // Progress and Settings
        tapTab(app, "Progress")
        XCTAssertTrue(element(app, containing: "routines done").waitForExistence(timeout: 10))
        shot("30-progress-free")
        tapTab(app, "Settings")
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 10))
        shot("40-settings")

        // A Pro routine opens the paywall
        tapTab(app, "Routines")
        let locked = element(app, containing: "Tech-Neck Relief")
        XCTAssertTrue(locked.waitForExistence(timeout: 10))
        locked.tap()
        XCTAssertTrue(element(app, containing: "Unlimited posture sessions").waitForExistence(timeout: 15))
        sleep(3)
        shot("50-paywall-from-locked-routine")
    }

    func testProUnlocksEverything() {
        let app = launch(["-NLSkipOnboarding", "-NLPro"])
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 20))
        shot("60-today-pro")

        tapTab(app, "Routines")
        let pro = element(app, containing: "Tech-Neck Relief")
        XCTAssertTrue(pro.waitForExistence(timeout: 10))
        shot("61-routines-pro")
        pro.tap()
        XCTAssertTrue(app.buttons["Skip this stretch"].waitForExistence(timeout: 10),
                      "Pro routine should start instead of showing the paywall")
        app.buttons["Close"].tap()

        tapTab(app, "Progress")
        XCTAssertTrue(element(app, containing: "routines done").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["See your trends with Pro"].exists)
        shot("62-progress-pro")

        tapTab(app, "Settings")
        XCTAssertTrue(element(app, containing: "Neckline Pro is active").waitForExistence(timeout: 10))
        shot("63-settings-pro")
    }

    /// Steps in the free Desk Reset routine (see `Routine.deskReset`).
    private static let deskResetSteps = 5
}
