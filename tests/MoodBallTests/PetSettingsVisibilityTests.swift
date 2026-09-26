import XCTest
@testable import MoodBall

@MainActor
final class PetSettingsVisibilityTests: XCTestCase {
    func testPetVisibilityMigratesAndCanBeShownAgain() {
        let suite = "MoodBallTests.PetVisibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "moodball.isBallVisible")

        let settings = PetSettings(defaults: defaults)
        XCTAssertFalse(settings.isPetVisible)

        settings.isPetVisible = true
        XCTAssertTrue(defaults.bool(forKey: "moodball.isPetVisible"))
        XCTAssertFalse(MoodBallShortcutAction.allCases.map(\.rawValue).contains("toggleBallVisibility"))
    }
}
