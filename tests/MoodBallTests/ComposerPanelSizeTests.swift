import AppKit
import XCTest
@testable import MoodBall

@MainActor
final class ComposerPanelSizeTests: XCTestCase {
    func testComposerPanelSizesFollowBarPhase() {
        let composerSize = NSSize(width: 340, height: 106)
        let resting = AppDelegate.composerPanelSize(
            for: .resting, expandedComposerSize: composerSize
        )
        let hovering = AppDelegate.composerPanelSize(
            for: .hovering, expandedComposerSize: composerSize
        )

        XCTAssertEqual(resting.width, MoodBallComposerView.restingPanelWidth)
        XCTAssertEqual(resting.height, MoodBallComposerView.restingPanelHeight)
        XCTAssertEqual(hovering.width, MoodBallComposerView.expandedBarPanelWidth)
        XCTAssertEqual(hovering.height, MoodBallComposerView.expandedBarPanelHeight)
        XCTAssertEqual(
            AppDelegate.composerPanelSize(
                for: .composer, expandedComposerSize: composerSize
            ),
            composerSize
        )
    }
}
