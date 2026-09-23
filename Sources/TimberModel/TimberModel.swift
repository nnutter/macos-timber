import Foundation

// Pure model logic for the Timber menubar app, ported from TimberModel.js
// in omarchy-timber (which itself mirrors timber's tui_create_wizard.go).
// No UI or process dependencies so it stays unit-testable in isolation.

public struct TimberRepo: Equatable {
    public let name: String
    public init(name: String) {
        self.name = name
    }
}

public struct TimberWorktree: Equatable {
    public let name: String
    public let repo: String
    public let path: String
    public init(name: String, repo: String, path: String) {
        self.name = name
        self.repo = repo
        self.path = path
    }
}

public struct TimberItem: Equatable, Identifiable {
    /// Stable identity for SwiftUI rows: open and create rows never share
    /// a value within one listing, so kind+value is unique.
    public var id: String {
        "\(kind):\(value)"
    }

    public enum Kind: Equatable {
        case open
        case create
    }

    public let kind: Kind
    public let name: String
    public let repo: String
    /// "name@repo".
    public let value: String
    /// Worktree path for `.open` rows, empty for `.create` rows.
    public let path: String
    public init(kind: Kind, name: String, repo: String, value: String, path: String) {
        self.kind = kind
        self.name = name
        self.repo = repo
        self.value = value
        self.path = path
    }
}

public enum TimberModel {
    // MARK: - Values

    /// Split "name@repo" on the LAST "@". Returns nil unless qualified
    /// (both halves non-empty).
    public static func splitValue(_ value: String) -> (name: String, repo: String)? {
        guard let idx = value.lastIndex(of: "@") else { return nil }
        let name = String(value[..<idx])
        let repo = String(value[value.index(after: idx)...])
        guard !name.isEmpty, !repo.isEmpty else { return nil }
        return (name, repo)
    }

    public static func worktreeValue(name: String, repo: String) -> String {
        "\(name)@\(repo)"
    }

    // MARK: - Fuzzy matching

    /// Case-insensitive fuzzy match: every char of term appears in order.
    /// Returns match indexes, or nil for no match. Empty term matches all.
    public static func fuzzyMatch(term: String, target: String) -> [Int]? {
        let query = term.lowercased()
        let candidate = target.lowercased()
        if query.isEmpty {
            return []
        }
        var indexes: [Int] = []
        var pos = candidate.startIndex
        for ch in query {
            guard let found = candidate[pos...].firstIndex(of: ch) else { return nil }
            indexes.append(candidate.distance(from: candidate.startIndex, to: found))
            pos = candidate.index(after: found)
        }
        return indexes
    }

    private static func filterTerm(_ term: String, targets: [String]) -> [Int] {
        if term.isEmpty {
            return Array(targets.indices)
        }
        return targets.indices.filter { fuzzyMatch(term: term, target: targets[$0]) != nil }
    }

    /// Split on the last separator. `qualified` is true only when both
    /// halves are non-empty; `before` is still usable for filtering when
    /// unqualified (e.g. "a@" filters on "a", "@b" matches everything).
    private struct SplitParts {
        let before: String
        let after: String
        let qualified: Bool
    }

    private static func cutLast(
        _ value: String,
        separator: Character
    ) -> SplitParts {
        guard let idx = value.lastIndex(of: separator) else {
            return SplitParts(before: value, after: "", qualified: false)
        }
        let before = String(value[..<idx])
        let after = String(value[value.index(after: idx)...])
        guard !before.isEmpty, !after.isEmpty else {
            return SplitParts(before: before, after: after, qualified: false)
        }
        return SplitParts(before: before, after: after, qualified: true)
    }

    /// Mirror filterWizardWorktrees: filter on the worktree half, then when
    /// the term is a qualified `name@repo`, intersect with the repo-half
    /// matches.
    static func filterWorktrees(_ term: String, worktrees: [TimberWorktree]) -> [Int] {
        let values = worktrees.map { worktreeValue(name: $0.name, repo: $0.repo) }
        let worktreeTargets = values.map { cutLast($0, separator: "@").before }
        let repoTargets = values.map { splitValue($0)?.repo ?? "" }
        let parts = cutLast(term, separator: "@")
        let worktreeRanks = filterTerm(parts.before, targets: worktreeTargets)
        guard parts.qualified else { return worktreeRanks }
        let repoSet = Set(filterTerm(parts.after, targets: repoTargets))
        return worktreeRanks.filter { repoSet.contains($0) }
    }

    // MARK: - Display items

    /// Mirror wizardItemsForTerm: existing worktrees first, then one
    /// `create` row per matching repo when the term is a qualified
    /// `name@repo` with no second `@` in the name half.
    public static func itemsForTerm(
        repos: [TimberRepo],
        worktrees: [TimberWorktree],
        term: String
    ) -> [TimberItem] {
        var items: [TimberItem] = []
        for rank in filterWorktrees(term, worktrees: worktrees) {
            let worktree = worktrees[rank]
            let value = worktreeValue(name: worktree.name, repo: worktree.repo)
            let item = TimberItem(
                kind: .open, name: worktree.name, repo: worktree.repo, value: value, path: worktree.path
            )
            items.append(item)
        }

        guard let termSplit = splitValue(term),
              !termSplit.name.isEmpty,
              !termSplit.name.contains("@")
        else { return items }

        let repoNames = repos.map(\.name)
        for repoIndex in filterTerm(termSplit.repo, targets: repoNames) {
            let repo = repos[repoIndex]
            let exists = worktrees.contains { $0.name == termSplit.name && $0.repo == repo.name }
            if exists {
                continue
            }
            let value = worktreeValue(name: termSplit.name, repo: repo.name)
            items.append(TimberItem(kind: .create, name: termSplit.name, repo: repo.name, value: value, path: ""))
        }
        return items
    }

    // MARK: - timber argv builders (after `timber`)

    /// `timber create [--herdr|--no-herdr] <name@repo>`.
    public static func createArgs(value: String, withHerdr: Bool) -> [String] {
        ["create", withHerdr ? "--herdr" : "--no-herdr", value]
    }

    /// `timber herdr space --new <name@repo>`.
    public static func herdrSpaceArgs(value: String) -> [String] {
        ["herdr", "space", "--new", value]
    }

    /// `timber remove <name@repo>`.
    public static func removeArgs(value: String) -> [String] {
        ["remove", value]
    }

    /// `timber repo add <url-or-path> [--name <name>]`. Returns nil when the
    /// URL is blank so callers can refuse to run instead of registering
    /// nothing. (This timber build has no `--alias` flag.)
    public static func repoAddArgs(url: String, name: String) -> [String]? {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return nil }
        var args = ["repo", "add"]
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty {
            args += ["--name", cleanName]
        }
        args.append(cleanURL)
        return args
    }

    // MARK: - Status-item clicks

    /// Left-click toggles the popover; right-click (or Ctrl-click) shows
    /// the context menu (Quit). Kept pure so the mapping stays tested.
    public enum StatusItemClickAction: Equatable {
        case togglePopover
        case showContextMenu
    }

    public static func statusItemClickAction(isSecondaryClick: Bool) -> StatusItemClickAction {
        isSecondaryClick ? .showContextMenu : .togglePopover
    }

    // MARK: - Notification routing

    /// True when running inside an `.app` bundle, the only context where
    /// UNUserNotificationCenter is safe to touch: from a raw binary it
    /// traps with `bundleProxyForCurrentProcess is nil`, which is
    /// uncatchable from Swift, so callers must use the osascript fallback.
    public static func usesUserNotifications(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.lowercased() == "app"
    }

    /// argv for `osascript` showing a notification; split out so the
    /// AppleScript quoting stays unit-tested.
    public static func appleScriptNotifyArgs(title: String, body: String) -> [String] {
        ["-e", "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"]
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Resource bundle lookup

    /// Locate `<name>.bundle` under the first candidate dir that
    /// contains it, without trapping: unlike the synthesized
    /// `Bundle.module` accessor (which calls fatalError when the bundle
    /// is missing), absence yields nil so callers can degrade gracefully
    /// (e.g. fall back to SF Symbols for icons).
    public static func resourceBundleURL(bundleName: String, candidateDirs: [URL]) -> URL? {
        for dir in candidateDirs {
            let url = dir.appendingPathComponent(bundleName + ".bundle", isDirectory: true)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    // MARK: - Child process environment

    /// PATH handed to `timber` children. GUI apps launch with a minimal
    /// PATH that lacks Homebrew etc., and `timber herdr` shells out to the
    /// `herdr` CLI via PATH lookup, so prepend the well-known install dirs
    /// (skipping ones already present).
    public static func childPATH(current: String?, extraDirs: [String]) -> String {
        let currentDirs = (current ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        let missing = extraDirs.filter { dir in !dir.isEmpty && !currentDirs.contains(dir) }
        return (missing + currentDirs).joined(separator: ":")
    }

    // MARK: - Two-phase delete

    /// One two-phase delete step for the armed value. Clicking the armed
    /// row confirms the remove; clicking any other row arms it instead
    /// (disarming the previous one). A blank value changes nothing.
    public static func armOrConfirmRemove(armed: String, value: String) -> (armed: String, confirmed: Bool) {
        guard !value.isEmpty else { return (armed, false) }
        if armed == value {
            return ("", true)
        }
        return (value, false)
    }
}
