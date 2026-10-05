@testable import TimberModel
import XCTest

final class TimberModelListStatusTests: XCTestCase {
    private let repos = [
        TimberRepo(name: "dispatch"),
        TimberRepo(name: "macos-timber"),
    ]

    func testListStatusTextInSyncIsEmpty() {
        XCTAssertEqual(TimberModel.listStatusText(merged: false, ahead: 0, behind: 0, statusError: false), "")
    }

    func testListStatusTextAheadAndBehind() {
        XCTAssertEqual(TimberModel.listStatusText(merged: false, ahead: 77, behind: 0, statusError: false), "↑77")
        XCTAssertEqual(TimberModel.listStatusText(merged: false, ahead: 0, behind: 3, statusError: false), "↓3")
        XCTAssertEqual(
            TimberModel.listStatusText(merged: false, ahead: 1, behind: 2, statusError: false),
            "↑1 ↓2"
        )
    }

    func testListStatusTextMergedAndError() {
        // Merged names the state instead of divergence detail.
        XCTAssertEqual(
            TimberModel.listStatusText(merged: true, ahead: 3, behind: 1, statusError: false),
            "merged"
        )
        XCTAssertEqual(TimberModel.listStatusText(merged: false, ahead: 1, behind: 0, statusError: true), "error")
    }

    func testTodoTextHidesEmptyChecklist() {
        XCTAssertEqual(TimberModel.todoText(done: 0, total: 0), "")
        XCTAssertEqual(TimberModel.todoText(done: 1, total: 2), "1/2")
    }

    func testItemsCarryStatusAndTodo() {
        let worktrees = [
            TimberWorktree(
                name: "alpha", repo: "dispatch", path: "/wt/dispatch/alpha/dispatch",
                ahead: 77, todoDone: 1, todoTotal: 2
            ),
            TimberWorktree(name: "status", repo: "macos-timber", path: "/wt/macos-timber/status/macos-timber"),
        ]
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "")
        let alpha = items.first(where: { $0.value == "alpha@dispatch" })
        XCTAssertEqual(alpha?.statusText, "↑77")
        XCTAssertEqual(alpha?.todoText, "1/2")
        let quiet = items.first(where: { $0.value == "status@macos-timber" })
        XCTAssertEqual(quiet?.statusText, "")
        XCTAssertEqual(quiet?.todoText, "")
    }
}
