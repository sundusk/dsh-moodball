import XCTest
@testable import MoodBall

final class MoodBallCommandClientTests: XCTestCase {
    @MainActor
    func testViewingCompletedTaskDoesNotDrivePetSnapshot() {
        let suiteName = "MoodBallCommandClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("completed-session", forKey: "moodball.command.sessionID")

        let client = MoodBallCommandClient(
            defaults: defaults,
            socketPath: "/tmp/moodball-command-client-tests-unused.sock"
        )
        let completedTask = MoodBallTaskSummary(
            sessionID: "completed-session",
            workspaceID: "workspace",
            title: "已完成任务",
            cwd: nil,
            updatedAt: 1,
            running: false,
            blank: false,
            state: .completed,
            mood: "done",
            taskRunning: false,
            waitingForUser: false,
            failed: false,
            completed: true,
            tool: nil,
            message: nil
        )

        client.applyTaskSummaries([completedTask])
        client.focusTask(completedTask.id)

        XCTAssertEqual(client.focusedTask?.id, completedTask.id)
        XCTAssertEqual(client.focusedTask?.statusLabel, "已完成")
        XCTAssertNil(client.sessionSnapshot)
    }
}
