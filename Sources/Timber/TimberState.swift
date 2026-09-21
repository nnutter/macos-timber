import Foundation
import SwiftUI
import TimberModel

// MARK: - State

/// Selection is tracked by row id, never by numeric index: typing rebuilds
/// the list on every keystroke, and a stale index into a shorter array
/// traps (Array._checkSubscript). Rows likewise receive their item value
/// directly instead of subscripting the array in `body`.
final class TimberState: ObservableObject {
    @Published var filter = ""
    @Published var items: [TimberItem] = []
    @Published var repos: [TimberRepo] = []
    @Published var worktrees: [TimberWorktree] = []
    @Published var selectedID: TimberItem.ID?
    @Published var cursorActive = false
    @Published var armedRemoveValue = ""
    @Published var repoFormOpen = false
    @Published var repoURL = ""
    @Published var repoName = ""
    @Published var busy = false
    @Published var listing = true

    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func background(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    func selectedItem() -> TimberItem? {
        items.first(where: { $0.id == selectedID })
    }

    // MARK: List

    /// Background poll: reload repos/worktrees without disturbing an open
    /// popover — filter text, selection, and cursor stay as they are.
    func refreshInBackground() {
        background {
            let (repos, worktrees) = TimberCommand.enumerate()
            self.onMain {
                self.repos = repos
                self.worktrees = worktrees
                self.listing = false
                self.rebuild()
            }
        }
    }

    /// Open the popover instantly from the warmed cache: clear the filter,
    /// reset selection, and rebuild without waiting on `timber`. Callers
    /// follow with `refreshInBackground()` to catch up quietly.
    func presentFromCache() {
        filter = ""
        selectedID = nil
        cursorActive = false
        armedRemoveValue = ""
        rebuild()
    }

    func refresh() {
        filter = ""
        selectedID = nil
        cursorActive = false
        armedRemoveValue = ""
        listing = true
        background {
            let (repos, worktrees) = TimberCommand.enumerate()
            self.onMain {
                self.repos = repos
                self.worktrees = worktrees
                self.listing = false
                self.rebuild()
            }
        }
    }

    /// Called by the filter field's onChange (the binding owns the text).
    func filterChanged() {
        selectedID = nil
        cursorActive = true
        rebuild()
    }

    func clearFilter() {
        filter = ""
    }

    func rebuild() {
        // Any list change disarms a pending delete.
        armedRemoveValue = ""
        items = TimberModel.itemsForTerm(repos: repos, worktrees: worktrees, term: filter)
        if let id = selectedID, items.contains(where: { $0.id == id }) {
            return
        }
        selectedID = items.first?.id
    }

    func select(id: TimberItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        cursorActive = true
        selectedID = id
        armedRemoveValue = ""
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        if !cursorActive {
            cursorActive = true
            selectedID = (delta < 0 ? items.last : items.first)?.id
        } else {
            let current = items.firstIndex(where: { $0.id == selectedID }) ?? 0
            let next = (current + delta + items.count) % items.count
            selectedID = items[next].id
        }
        armedRemoveValue = ""
    }

    // MARK: Actions

    /// Return / row click: open in Zed (creating first for create rows).
    func primaryAction() {
        guard !busy, !items.isEmpty else { return }
        if cursorActive, let item = selectedItem() {
            activate(item)
        } else {
            cursorActive = true
            if selectedID == nil {
                selectedID = items.first?.id
            }
        }
    }

    func clickActivate(_ item: TimberItem) {
        guard !busy, items.contains(where: { $0.id == item.id }) else { return }
        select(id: item.id)
        activate(item)
    }

    func activate(_ item: TimberItem) {
        if item.kind == .open {
            openInZed(item)
        } else {
            create(item, withHerdr: false)
        }
    }
}
