@testable import TimberModel
import XCTest

final class TimberModelTests: XCTestCase {
    private let repos = [
        TimberRepo(name: "timber"),
        TimberRepo(name: "scribble"),
    ]
    private let worktrees = [
        TimberWorktree(name: "feature/login", repo: "timber", path: "/wt/timber/feature/login/timber"),
        TimberWorktree(name: "fix-crash", repo: "scribble", path: "/wt/scribble/fix-crash/scribble"),
    ]

    // MARK: - splitValue

    func testSplitValueQualified() {
        let split = TimberModel.splitValue("feature/login@timber")
        XCTAssertEqual(split?.name, "feature/login")
        XCTAssertEqual(split?.repo, "timber")
    }

    func testSplitValueSplitsOnLastAt() {
        let split = TimberModel.splitValue("a@b@c")
        XCTAssertEqual(split?.name, "a@b")
        XCTAssertEqual(split?.repo, "c")
    }

    func testSplitValueUnqualified() {
        XCTAssertNil(TimberModel.splitValue("plain"))
        XCTAssertNil(TimberModel.splitValue("name@"))
        XCTAssertNil(TimberModel.splitValue("@repo"))
        XCTAssertNil(TimberModel.splitValue(""))
    }

    // MARK: - fuzzyMatch

    func testFuzzyMatchInOrder() {
        XCTAssertNotNil(TimberModel.fuzzyMatch(term: "fl", target: "feature/login"))
        XCTAssertNotNil(TimberModel.fuzzyMatch(term: "FLogin", target: "feature/login"))
    }

    func testFuzzyMatchOutOfOrderFails() {
        XCTAssertNil(TimberModel.fuzzyMatch(term: "lf", target: "feature/login"))
        XCTAssertNil(TimberModel.fuzzyMatch(term: "zzz", target: "feature/login"))
    }

    func testFuzzyMatchEmptyTermMatchesAll() {
        XCTAssertEqual(TimberModel.fuzzyMatch(term: "", target: "anything"), [])
    }

    // MARK: - itemsForTerm

    func testEmptyTermListsAllWorktrees() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "")
        XCTAssertEqual(items.map(\.value), ["feature/login@timber", "fix-crash@scribble"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .open })
        XCTAssertEqual(items[0].path, "/wt/timber/feature/login/timber")
    }

    func testFilterMatchesWorktreeHalf() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "fix")
        XCTAssertEqual(items.map(\.value), ["fix-crash@scribble"])
    }

    func testQualifiedTermIntersectsRepoHalf() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "f@timber")
        XCTAssertEqual(
            items.map { ($0.kind, $0.value) }.map { "\($0.0):\($0.1)" },
            ["open:feature/login@timber", "create:f@timber"]
        )
    }

    func testQualifiedTermYieldsOnlyCreateRowWhenNothingOpen() {
        // "login" matches no worktree under scribble, so the only row
        // offers to create login@scribble.
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "login@scribble")
        XCTAssertEqual(items.map { ($0.kind, $0.value) }.map { "\($0.0):\($0.1)" }, ["create:login@scribble"])
    }

    func testQualifiedTermIntersectsBothHalves() {
        // "f" alone matches both worktrees; "@scribble" narrows the open
        // rows to one (plus the create offer for f@scribble).
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "f@scribble")
        XCTAssertEqual(
            items.map { ($0.kind, $0.value) }.map { "\($0.0):\($0.1)" },
            ["open:fix-crash@scribble", "create:f@scribble"]
        )
    }

    func testCreateRowForNewQualifiedValue() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "new-thing@tim")
        XCTAssertEqual(items.map { ($0.kind, $0.value) }.map { "\($0.0):\($0.1)" }, ["create:new-thing@timber"])
        XCTAssertEqual(items[0].path, "")
    }

    func testNoCreateRowWhenWorktreeExists() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "feature/login@timber")
        XCTAssertEqual(items.map(\.kind), [.open])
    }

    func testNoCreateRowWhenTermUnqualified() {
        let items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: "new-thing")
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - row identity

    func testItemIDsUniqueWithinListing() {
        // The popover diffs rows by id; a duplicate would collapse two
        // rows into one and desync selection. Exercise open-heavy,
        // create-heavy, and empty terms.
        for term in ["", "f", "f@timber", "new@tim", "login@scribble", "@", "zzz"] {
            let ids = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: term).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "duplicate row ids for term \(term.debugDescription)")
        }
    }

    // MARK: - status-item clicks

    func testSecondaryClickShowsContextMenu() {
        XCTAssertEqual(
            TimberModel.statusItemClickAction(isSecondaryClick: true),
            .showContextMenu
        )
    }

    func testPrimaryClickTogglesPopover() {
        XCTAssertEqual(
            TimberModel.statusItemClickAction(isSecondaryClick: false),
            .togglePopover
        )
    }

    // MARK: - notification routing

    func testUsesUserNotificationsOnlyInsideAppBundle() {
        XCTAssertTrue(TimberModel
            .usesUserNotifications(bundleURL: URL(fileURLWithPath: "/Applications/Timber.app")))
        XCTAssertFalse(TimberModel
            .usesUserNotifications(
                bundleURL: URL(fileURLWithPath: "/Users/nnutter/worktrees/macos-timber/alpha/macos-timber/dist")
            ))
        XCTAssertFalse(TimberModel
            .usesUserNotifications(
                bundleURL: URL(fileURLWithPath: "/Users/nnutter/worktrees/macos-timber/alpha/macos-timber/.build/debug")
            ))
    }

    func testAppleScriptNotifyArgs() {
        XCTAssertEqual(
            TimberModel.appleScriptNotifyArgs(title: "Timber Hi", body: "done"),
            ["-e", "display notification \"done\" with title \"Timber Hi\""]
        )
    }

    func testAppleScriptNotifyArgsEscapesQuotes() {
        // A quote or backslash in the detail must not break out of the
        // AppleScript string literal (or the notify fallback crashes).
        XCTAssertEqual(
            TimberModel.appleScriptNotifyArgs(title: "Timber x", body: #"said "hi" C:\wt"#),
            ["-e", #"display notification "said \"hi\" C:\\wt" with title "Timber x""#]
        )
    }

    // MARK: - child PATH

    func testChildPATHPrependsMissingDirs() {
        XCTAssertEqual(
            TimberModel.childPATH(current: "/usr/bin:/bin", extraDirs: ["/opt/homebrew/bin", "/usr/bin"]),
            "/opt/homebrew/bin:/usr/bin:/bin"
        )
    }

    func testChildPATHHandlesNilAndEmpty() {
        XCTAssertEqual(TimberModel.childPATH(current: nil, extraDirs: ["/opt/homebrew/bin"]), "/opt/homebrew/bin")
        XCTAssertEqual(TimberModel.childPATH(current: "", extraDirs: []), "")
    }

    // MARK: - argv builders

    func testCreateArgs() {
        XCTAssertEqual(
            TimberModel.createArgs(value: "x@timber", withHerdr: false),
            ["create", "--no-herdr", "x@timber"]
        )
        XCTAssertEqual(TimberModel.createArgs(value: "x@timber", withHerdr: true), ["create", "--herdr", "x@timber"])
    }

    func testHerdrSpaceArgs() {
        XCTAssertEqual(TimberModel.herdrSpaceArgs(value: "x@timber"), ["herdr", "space", "--new", "x@timber"])
    }

    func testRemoveArgs() {
        XCTAssertEqual(TimberModel.removeArgs(value: "x@timber"), ["remove", "x@timber"])
    }

    func testRepoAddArgs() {
        XCTAssertEqual(
            TimberModel.repoAddArgs(url: " https://example.com/r.git ", name: " r "),
            ["repo", "add", "--name", "r", "https://example.com/r.git"]
        )
        XCTAssertEqual(
            TimberModel.repoAddArgs(url: "https://example.com/r.git", name: "  "),
            ["repo", "add", "https://example.com/r.git"]
        )
        XCTAssertNil(TimberModel.repoAddArgs(url: "   ", name: "r"))
    }

    // MARK: - two-phase delete

    func testArmOrConfirmRemove() {
        XCTAssertEqual(TimberModel.armOrConfirmRemove(armed: "", value: "x@r").armed, "x@r")
        XCTAssertFalse(TimberModel.armOrConfirmRemove(armed: "", value: "x@r").confirmed)
        let confirm = TimberModel.armOrConfirmRemove(armed: "x@r", value: "x@r")
        XCTAssertEqual(confirm.armed, "")
        XCTAssertTrue(confirm.confirmed)
        let switchRow = TimberModel.armOrConfirmRemove(armed: "x@r", value: "y@r")
        XCTAssertEqual(switchRow.armed, "y@r")
        XCTAssertFalse(switchRow.confirmed)
        let blank = TimberModel.armOrConfirmRemove(armed: "x@r", value: "")
        XCTAssertEqual(blank.armed, "x@r")
        XCTAssertFalse(blank.confirmed)
    }
}
