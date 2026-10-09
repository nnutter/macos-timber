import Combine
import Foundation
@testable import Timber
import TimberModel
import XCTest

final class TimberEnumerationTests: XCTestCase {
    func testEnumerationUsesCLIIdentitiesAndPathsOutsideManagedLayout() throws {
        let json = """
        [
          {"name":"feature/topic","repo":"sample","path":"/custom/checkouts/review copy",
           "ahead":2,"behind":1,"todoDone":1,"todoTotal":3},
          {"name":"other/review copy","repo":"sample","path":"/elsewhere/review copy",
           "statusError":true},
          {"name":"standard","repo":"sample","path":"/worktrees/sample/standard/sample","merged":true}
        ]
        """
        try withTimber(listJSON: json) {
            let (repos, worktrees) = try TimberCommand.enumerate()
            XCTAssertEqual(repos, [TimberRepo(name: "sample")])
            let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "", sort: .worktree)
            XCTAssertEqual(items, [
                TimberItem(
                    kind: .open, name: "feature/topic", repo: "sample", value: "feature/topic@sample",
                    path: "/custom/checkouts/review copy", statusText: "↑2 ↓1", todoText: "1/3"
                ),
                TimberItem(
                    kind: .open, name: "other/review copy", repo: "sample", value: "other/review copy@sample",
                    path: "/elsewhere/review copy", statusText: "error"
                ),
                TimberItem(
                    kind: .open, name: "standard", repo: "sample", value: "standard@sample",
                    path: "/worktrees/sample/standard/sample", statusText: "merged"
                ),
            ])
        }
    }

    func testEnumerationDistinguishesEmptyListingFromFailedListing() throws {
        try withTimber(listJSON: "[]") {
            let (_, worktrees) = try TimberCommand.enumerate()
            XCTAssertTrue(worktrees.isEmpty)
        }
        try withTimber(listJSON: "[]", exitCode: 1) {
            XCTAssertThrowsError(try TimberCommand.enumerate())
        }
        try withTimber(listJSON: "not JSON") {
            XCTAssertThrowsError(try TimberCommand.enumerate())
        }
        try withTimber(listJSON: #"[{"name":"feature","repo":"sample"}]"#) {
            XCTAssertThrowsError(try TimberCommand.enumerate())
        }
    }

    func testFailedBackgroundRefreshPreservesVisibleRowsAndFilter() throws {
        try withTimber(listJSON: "[]", exitCode: 1) {
            let state = TimberState()
            state.repos = [TimberRepo(name: "sample")]
            state.worktrees = [TimberWorktree(name: "feature", repo: "sample", path: "/custom/checkout")]
            state.filter = "feature"
            state.rebuild()
            state.cursorActive = true
            let originalItems = state.items
            let originalSelection = state.selectedID
            let completed = expectation(description: "Background refresh completes")
            let subscription = state.$listing.dropFirst().sink { listing in
                if !listing {
                    completed.fulfill()
                }
            }
            defer { subscription.cancel() }

            state.refreshInBackground()
            wait(for: [completed], timeout: 5)

            XCTAssertEqual(state.items, originalItems)
            XCTAssertEqual(state.worktrees, [TimberWorktree(name: "feature", repo: "sample", path: "/custom/checkout")])
            XCTAssertEqual(state.repos, [TimberRepo(name: "sample")])
            XCTAssertEqual(state.filter, "feature")
            XCTAssertEqual(state.selectedID, originalSelection)
            XCTAssertTrue(state.cursorActive)
        }
    }

    private func withTimber(listJSON: String, exitCode: Int = 0, body: () throws -> Void) throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        try Data(listJSON.utf8).write(to: directory.appendingPathComponent("listing.json"))
        let script = """
        #!/bin/sh
        case "$1" in
          repo) printf 'sample\\n' ;;
          list) /bin/cat "$(/usr/bin/dirname "$0")/listing.json"; exit \(exitCode) ;;
          *) exit 2 ;;
        esac
        """
        let executable = directory.appendingPathComponent("timber")
        try Data(script.utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let originalPATH = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", directory.path, 1)
        defer {
            if let originalPATH {
                setenv("PATH", originalPATH, 1)
            } else {
                unsetenv("PATH")
            }
        }
        try body()
    }
}
