import Foundation
import TimberModel
import UserNotifications

// Shell-out layer: runs the `timber` CLI, enumerates repos/worktrees the
// same way omarchy-timber's listScript does, opens paths in Zed, and posts
// notifications. Menubar apps launched from Finder do not inherit a shell
// PATH, so executables are located by searching well-known directories.

enum TimberCommand {
    struct RunResult {
        let code: Int32
        let stdout: String
        let stderr: String
    }

    private static let searchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
        "/usr/bin",
        "/bin",
    ]

    /// Locate an executable, honoring the inherited PATH first (covers
    /// `swift run` / Terminal launches) then well-known install dirs.
    static func findExecutable(_ name: String) -> URL? {
        if name.contains("/") {
            let url = URL(fileURLWithPath: name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            return nil
        }
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + searchDirs {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Run `timber <args>`, capturing output. Throws if timber is missing
    /// or the process cannot start.
    @discardableResult
    static func runTimber(_ args: [String]) throws -> RunResult {
        guard let exe = findExecutable("timber") else {
            let message = "timber executable not found in PATH"
                + " or /opt/homebrew/bin, /usr/local/bin, ~/.local/bin"
            throw NSError(
                domain: "Timber", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return try run(exe, args: args)
    }

    static func run(_ exe: URL, args: [String]) throws -> RunResult {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        // Children (notably `timber herdr`, which shells out to `herdr`)
        // inherit this PATH, so augment it: GUI launches provide only
        // /usr/bin:/bin:/usr/sbin:/sbin.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = TimberModel.childPATH(current: env["PATH"], extraDirs: searchDirs)
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(code: proc.terminationStatus, stdout: out, stderr: err)
    }

    // MARK: - Enumeration

    /// Same enumeration timber's own zsh completion uses: registered repo
    /// names plus a scan of the worktree root for `<root>/<repo>/**/<repo>`
    /// directories containing `.git`. `timber list` is avoided on purpose —
    /// its styled table still emits ANSI under NO_COLOR and it enriches
    /// every row with git status, so one missing worktree directory fails
    /// the whole listing.
    static func enumerate() -> (repos: [TimberRepo], worktrees: [TimberWorktree]) {
        let fm = FileManager.default
        var repoNames: [String] = []
        if let result = try? runTimber(["repo", "list", "-q"]), result.code == 0 {
            repoNames = result.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if repoNames.isEmpty {
            let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/share").path
            let reposDir = URL(fileURLWithPath: dataHome).appendingPathComponent("timber/repos")
            if let bare = try? fm.contentsOfDirectory(atPath: reposDir.path) {
                repoNames = bare.filter { $0.hasSuffix(".git") }.map { String($0.dropLast(4)) }.sorted()
            }
        }

        let root = ProcessInfo.processInfo.environment["TIMBER_WORKTREE_ROOT"]
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("worktrees").path
        var worktrees: [TimberWorktree] = []
        for repo in repoNames {
            let base = URL(fileURLWithPath: root).appendingPathComponent(repo)
            for dir in walkDirectories(at: base, matching: repo, maxDepth: 8) {
                let parent = dir.deletingLastPathComponent()
                let rel = parent.path.hasPrefix(base.path + "/")
                    ? String(parent.path.dropFirst(base.path.count + 1))
                    : ""
                guard !rel.isEmpty else { continue }
                worktrees.append(TimberWorktree(name: rel, repo: repo, path: dir.path))
            }
        }
        return (repoNames.map { TimberRepo(name: $0) }, worktrees.sorted { $0.value < $1.value })
    }

    /// Directories named `name` containing a `.git` entry, up to maxDepth
    /// below (and excluding) the base itself.
    private static func walkDirectories(at base: URL, matching name: String, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        var stack: [(URL, Int)] = [(base, 0)]
        let fm = FileManager.default
        while let (dir, depth) = stack.popLast() {
            guard depth < maxDepth else { continue }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                if entry.lastPathComponent == "node_modules" {
                    continue
                }
                if entry.lastPathComponent == name {
                    if fm.fileExists(atPath: entry.appendingPathComponent(".git").path) {
                        found.append(entry)
                    }
                }
                stack.append((entry, depth + 1))
            }
        }
        return found
    }

    // MARK: - Open

    /// Open a path in Zed (`zed --new`), falling back to Finder `open`
    /// when Zed is not installed.
    static func openPath(_ path: String) throws {
        if let zed = findExecutable("zed") {
            let result = try run(zed, args: ["--new", path])
            if result.code == 0 {
                return
            }
        }
        guard let open = findExecutable("open") else {
            throw NSError(
                domain: "Timber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "neither zed nor open found"]
            )
        }
        _ = try run(open, args: [path])
    }

    // MARK: - Notifications

    /// Post a user notification (failures critical-style via title prefix;
    /// UNUserNotificationCenter has no urgency levels for local notes).
    /// Never throws: notification failure must not break the action.
    ///
    /// UNUserNotificationCenter requires app-bundle identity and traps
    /// (`bundleProxyForCurrentProcess is nil`, uncatchable from Swift)
    /// when called from a raw binary, so outside an `.app` bundle this
    /// falls back to `osascript display notification`.
    static func notify(subject: String, detail: String, failure: Bool = false) {
        let title = failure ? "Timber \(subject) failed" : "Timber \(subject)"
        let body = detail.isEmpty ? (failure ? "unknown error" : "done") : detail
        if TimberModel.usesUserNotifications(bundleURL: Bundle.main.bundleURL) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString, content: content, trigger: nil
                )
                center.add(request)
            }
        } else if let osascript = findExecutable("osascript") {
            _ = try? run(osascript, args: TimberModel.appleScriptNotifyArgs(title: title, body: body))
        }
    }
}

private extension TimberWorktree {
    var value: String {
        TimberModel.worktreeValue(name: name, repo: repo)
    }
}
