import AppKit
import SwiftUI
import TimberModel

// Popover views: fuzzy-filter list over worktrees plus the row layout.
// Kept apart from the AppKit lifecycle in TimberApp so neither file
// trips the line-count lint.

// MARK: - Views

struct TimberPopover: View {
    @ObservedObject var state: TimberState
    @FocusState private var filterFocused: Bool
    @FocusState private var formFocused: Bool

    private let maxRows = 8
    private let rowHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("type worktree@repo", text: $state.filter)
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                    .onSubmit { state.primaryAction() }
                    .onChange(of: state.filter) { _, _ in state.filterChanged() }
                    .disabled(state.busy)

                if state.busy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                }

                Button(state.repoFormOpen ? "−" : "+") {
                    state.repoFormOpen.toggle()
                }
                .help(state.repoFormOpen ? "Close repository form" : "Add repository (timber repo add)")
                .disabled(state.busy)
            }

            Picker("Sort", selection: $state.sort) {
                ForEach(TimberModel.SortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Sort worktrees (timber list --sort)")
            .onChange(of: state.sort) { _, _ in state.rebuild() }

            if state.repoFormOpen {
                TextField("Remote URL or path", text: $state.repoURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($formFocused)
                    .onSubmit { state.submitRepoForm() }
                    .disabled(state.busy)
                TextField("Name (optional, derived from URL)", text: $state.repoName)
                    .textFieldStyle(.roundedBorder)
                    .focused($formFocused)
                    .onSubmit { state.submitRepoForm() }
                    .disabled(state.busy)
                HStack(spacing: 8) {
                    Button(state.busy ? "Adding…" : "Add repository") {
                        state.submitRepoForm()
                    }
                    .disabled(state.busy)
                    Button("Cancel") {
                        state.repoFormOpen = false
                    }
                    .disabled(state.busy)
                }
            }

            if state.listing {
                Text("Loading worktrees…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if state.items.isEmpty {
                Text(state.worktrees.isEmpty
                    ? "No worktrees yet — type name@repo to create one"
                    : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(state.items) { item in
                            TimberRow(state: state, item: item)
                        }
                    }
                }
                .frame(maxHeight: CGFloat(maxRows) * rowHeight)
            }
        }
        .padding()
        .frame(minWidth: PopoverSizing.minWidth, maxWidth: PopoverSizing.maxWidth)
        .onAppear {
            filterFocused = true
        }
        .onKeyPress(.upArrow) { state.move(-1); return .handled }
        .onKeyPress(.downArrow) { state.move(1); return .handled }
        .onKeyPress(.escape) {
            if formFocused {
                return .ignored
            }
            if state.repoFormOpen {
                state.repoFormOpen = false
            } else if !state.filter.isEmpty {
                state.clearFilter()
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "u"), phases: .down) { press in
            guard press.modifiers == .control, !formFocused else { return .ignored }
            state.clearFilter()
            return .handled
        }
    }
}

struct TimberRow: View {
    @ObservedObject var state: TimberState
    let item: TimberItem

    private var selected: Bool {
        state.cursorActive && state.selectedID == item.id
    }

    private var armed: Bool {
        state.armedRemoveValue == item.value
    }

    private let iconBox: CGFloat = 22
    private let iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3, height: 20)
                .opacity(selected ? 1 : 0)

            Text((item.kind == .create ? "+ " : "") + item.value)
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(item.kind == .create && !selected ? 0.72 : 1)

            Spacer(minLength: 8)

            // The action cluster is always in the layout (hidden when the
            // row is not selected) so the popover width never jumps and
            // the window never clips the row when buttons appear.
            HStack(spacing: 4) {
                Button {
                    state.openInZed(item)
                } label: {
                    Image(nsImage: TimberIcons.zed)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .frame(width: iconBox, height: iconBox)
                .help(item.kind == .open ? "Open in Zed" : "Create and open in Zed")

                Button {
                    state.openInHerdr(item)
                } label: {
                    Image(nsImage: TimberIcons.herdr)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .frame(width: iconBox, height: iconBox)
                .help(item.kind == .open ? "Open in Herdr" : "Create in Herdr")

                if item.kind == .open {
                    Button {
                        state.armOrRemove(item)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: iconSize, height: iconSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: iconBox, height: iconBox)
                    .foregroundStyle(armed ? .red : .primary)
                    .help(armed ? "Click again to remove \(item.value)" : "Remove \(item.value)")
                } else {
                    // Invisible placeholder keeps the cluster width stable.
                    Image(systemName: "trash")
                        .frame(width: iconSize, height: iconSize)
                        .frame(width: iconBox, height: iconBox)
                        .opacity(0)
                }
            }
            .layoutPriority(1)
            .opacity(selected ? 1 : 0)
            .disabled(!selected || state.busy)
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                state.select(id: item.id)
            }
        }
        .onTapGesture {
            state.clickActivate(item)
        }
    }
}
