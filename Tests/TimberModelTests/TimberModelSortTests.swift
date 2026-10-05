@testable import TimberModel
import XCTest

final class TimberModelSortTests: XCTestCase {
    private let repos = [
        TimberRepo(name: "timber"),
        TimberRepo(name: "scribble"),
    ]
    private let worktrees = [
        TimberWorktree(name: "feature/login", repo: "timber", path: "/wt/timber/feature/login/timber"),
        TimberWorktree(name: "fix-crash", repo: "scribble", path: "/wt/scribble/fix-crash/scribble"),
    ]

    func testSortWorktreesByRepo() {
        let sorted = TimberModel.sortWorktrees(worktrees, mode: .repo)
        XCTAssertEqual(sorted.map(\.repo), ["scribble", "timber"])
    }

    func testSortWorktreesByWorktree() {
        let sorted = TimberModel.sortWorktrees(worktrees, mode: .worktree)
        XCTAssertEqual(sorted.map(\.name), ["feature/login", "fix-crash"])
    }

    func testSortWorktreesByRecencyNewestFirst() {
        let old = TimberWorktree(
            name: "aaa", repo: "zzz", path: "/wt/old", lastCommitAt: Date(timeIntervalSince1970: 100)
        )
        let new = TimberWorktree(
            name: "zzz", repo: "aaa", path: "/wt/new", lastCommitAt: Date(timeIntervalSince1970: 200)
        )
        // Recency wins over name/repo ordering.
        XCTAssertEqual(TimberModel.sortWorktrees([old, new], mode: .recency).map(\.name), ["zzz", "aaa"])
    }

    func testSortWorktreesByRecencyMissingDatesLast() {
        let dated = TimberWorktree(
            name: "b", repo: "b", path: "/wt/b", lastCommitAt: Date(timeIntervalSince1970: 100)
        )
        let undated = TimberWorktree(name: "a", repo: "a", path: "/wt/a")
        XCTAssertEqual(TimberModel.sortWorktrees([undated, dated], mode: .recency).map(\.name), ["b", "a"])
    }

    func testItemsForTermRespectsSortMode() {
        let ordered = [
            TimberWorktree(name: "b", repo: "a", path: "/wt/b"),
            TimberWorktree(name: "a", repo: "b", path: "/wt/a"),
        ]
        let byRepo = TimberModel.itemsForTerm(repos: repos, worktrees: ordered, term: "", sort: .repo)
        XCTAssertEqual(byRepo.map(\.value), ["b@a", "a@b"])
        let byWorktree = TimberModel.itemsForTerm(repos: repos, worktrees: ordered, term: "", sort: .worktree)
        XCTAssertEqual(byWorktree.map(\.value), ["a@b", "b@a"])
    }
}
