import Foundation
import SwiftUI
import TimberModel

// MARK: - TimberState actions

extension TimberState {
    func openInZed(_ item: TimberItem) {
        if item.kind == .open {
            guard !busy, !item.path.isEmpty else { return }
            busy = true
            background {
                try? TimberCommand.openPath(item.path)
                self.onMain { self.busy = false }
            }
        } else {
            create(item, withHerdr: false)
        }
    }

    func openInHerdr(_ item: TimberItem) {
        guard !busy else { return }
        if item.kind == .open {
            busy = true
            background {
                do {
                    let result = try TimberCommand.runTimber(TimberModel.herdrSpaceArgs(value: item.value))
                    self.onMain {
                        self.busy = false
                        if result.code == 0 {
                            TimberCommand.notify(subject: "Herdr space created", detail: item.value)
                        } else {
                            TimberCommand.notify(
                                subject: "herdr space",
                                detail: Self.lastLine(result.stderr) ?? "exit \(result.code)",
                                failure: true
                            )
                        }
                    }
                } catch {
                    self.onMain {
                        self.busy = false
                        TimberCommand.notify(subject: "herdr space", detail: error.localizedDescription, failure: true)
                    }
                }
            }
        } else {
            create(item, withHerdr: true)
        }
    }

    /// Create the worktree; without Herdr the resulting path opens in Zed,
    /// with Herdr a notification posts instead (mirrors Panel.qml).
    func create(_ item: TimberItem, withHerdr: Bool) {
        guard !busy else { return }
        busy = true
        background {
            do {
                let args = TimberModel.createArgs(value: item.value, withHerdr: withHerdr)
                let result = try TimberCommand.runTimber(args)
                self.onMain {
                    self.busy = false
                    guard result.code == 0 else {
                        TimberCommand.notify(
                            subject: "worktree create",
                            detail: Self.lastLine(result.stderr) ?? "exit \(result.code)",
                            failure: true
                        )
                        return
                    }
                    if withHerdr {
                        TimberCommand.notify(subject: "Herdr space created", detail: item.value)
                        self.refresh()
                    } else if let path = Self.lastLine(result.stdout), !path.isEmpty {
                        self.clearFilter()
                        try? TimberCommand.openPath(path)
                    } else {
                        TimberCommand.notify(subject: "worktree create", detail: "reported no path", failure: true)
                    }
                }
            } catch {
                self.onMain {
                    self.busy = false
                    TimberCommand.notify(subject: "worktree create", detail: error.localizedDescription, failure: true)
                }
            }
        }
    }

    /// Two-phase delete: first click arms the row, second click removes.
    func armOrRemove(_ item: TimberItem) {
        guard item.kind == .open, !busy else { return }
        let step = TimberModel.armOrConfirmRemove(armed: armedRemoveValue, value: item.value)
        armedRemoveValue = step.armed
        if step.confirmed {
            remove(item)
        }
    }

    private func remove(_ item: TimberItem) {
        busy = true
        background {
            do {
                let result = try TimberCommand.runTimber(TimberModel.removeArgs(value: item.value))
                self.onMain {
                    self.busy = false
                    if result.code == 0 {
                        self.refresh()
                    } else {
                        TimberCommand.notify(
                            subject: "worktree remove",
                            detail: Self.lastLine(result.stderr) ?? "exit \(result.code)",
                            failure: true
                        )
                    }
                }
            } catch {
                self.onMain {
                    self.busy = false
                    TimberCommand.notify(subject: "worktree remove", detail: error.localizedDescription, failure: true)
                }
            }
        }
    }

    // MARK: Repo form

    func submitRepoForm() {
        guard !busy, let args = TimberModel.repoAddArgs(url: repoURL, name: repoName) else { return }
        busy = true
        background {
            do {
                let result = try TimberCommand.runTimber(args)
                self.onMain {
                    self.busy = false
                    if result.code == 0 {
                        self.repoFormOpen = false
                        self.repoURL = ""
                        self.repoName = ""
                        self.refresh()
                    } else {
                        TimberCommand.notify(
                            subject: "repo add",
                            detail: Self.lastLine(result.stderr) ?? "exit \(result.code)",
                            failure: true
                        )
                    }
                }
            } catch {
                self.onMain {
                    self.busy = false
                    TimberCommand.notify(subject: "repo add", detail: error.localizedDescription, failure: true)
                }
            }
        }
    }

    private static func lastLine(_ text: String) -> String? {
        let line = text.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (line?.isEmpty == false) ? line : nil
    }
}
