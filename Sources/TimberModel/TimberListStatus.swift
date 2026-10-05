import Foundation

// Status/Todo badges for the popover rows, mirroring the `timber ls`
// columns (minus the `[<upstream>]` suffix). Pure logic next to
// TimberModel so it stays unit-tested in isolation.

public extension TimberModel {
    /// Status column from `timber ls`, minus the `[<upstream>]` suffix:
    /// `merged` names the state instead of divergence detail, otherwise
    /// ahead/behind counts render as arrows, and unreadable git status
    /// reports `error`. Empty when the worktree is in sync. Counts are
    /// unpadded: the popover never aligns a column across rows.
    static func listStatusText(merged: Bool, ahead: Int, behind: Int, statusError: Bool) -> String {
        if statusError {
            return "error"
        }
        if merged {
            return "merged"
        }
        var parts: [String] = []
        if ahead > 0 {
            parts.append("↑\(ahead)")
        }
        if behind > 0 {
            parts.append("↓\(behind)")
        }
        return parts.joined(separator: " ")
    }

    /// Todo column from `timber ls` (`done/total`). Empty when the
    /// worktree has no checklist items, so quiet rows stay quiet.
    static func todoText(done: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(done)/\(total)"
    }
}
