import XCTest
@testable import MoodBall

@MainActor
final class PetSettingsVisibilityTests: XCTestCase {
    func testPetVisibilityMigratesAndDoesNotChangeMiniMode() {
        let suite = "MoodBallTests.PetVisibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "moodball.isBallVisible")
        defaults.set(FloatingDisplayMode.controlsOnly.rawValue, forKey: "moodball.displayMode")

        let settings = PetSettings(defaults: defaults)
        XCTAssertFalse(settings.isPetVisible)
        XCTAssertEqual(settings.displayMode, .controlsOnly)

        settings.isPetVisible = true
        XCTAssertTrue(defaults.bool(forKey: "moodball.isPetVisible"))
        XCTAssertEqual(settings.displayMode, .controlsOnly)

        settings.displayMode = .petAndControls
        XCTAssertTrue(settings.isPetVisible)
        XCTAssertFalse(MoodBallShortcutAction.allCases.map(\.rawValue).contains("toggleBallVisibility"))
    }
}
