import AppKit
import SwiftUI
import TimberModel

// Timber menubar app: bar-widget frontend to `timber` (managed Git
// worktrees), ported from omarchy-timber's Panel.qml. Menubar icon plus
// popover: fuzzy filter over worktrees, open in Zed / Herdr, create,
// two-phase remove, and a `timber repo add` form.
//
// The status item is managed with AppKit rather than MenuBarExtra so
// left-click opens the popover while right-click shows a menu with Quit.

/// NSHostingView that keeps its NSPopover sized to the SwiftUI content.
/// Without this the popover opens at a pre-layout size (clipping rows)
/// and only reaches full size on a later open, after layout has resolved.
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: ((NSSize) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        onLayout?(fittingSize)
    }
}

/// Action icons, loaded from the bundled PNGs by explicit URL instead of
/// named lookup, with every scale wired so Retina picks the right
/// representation.
///
/// The bundle is located defensively and never via Bundle.module: its
/// synthesized accessor calls fatalError when the bundle is missing,
/// which crashed the popover on first open in v0.1.1. A missing bundle
/// or missing PNG degrades to an SF Symbol instead of trapping.
enum TimberIcons {
    static let zed = load("zed", fallbackSystemName: "terminal")
    static let herdr = load("herdr", fallbackSystemName: "server.rack")

    private static func load(_ name: String, fallbackSystemName: String) -> NSImage {
        if let image = bundledImage(named: name) {
            return image
        }
        return NSImage(systemSymbolName: fallbackSystemName, accessibilityDescription: name) ?? NSImage()
    }

    private static func bundledImage(named name: String) -> NSImage? {
        let dirs = candidateDirs()
        guard let bundleURL = TimberModel.resourceBundleURL(bundleName: "Timber_Timber", candidateDirs: dirs) else {
            return nil
        }
        guard let bundle = Bundle(url: bundleURL) else {
            return nil
        }
        let image = NSImage()
        var found = false
        for scale in ["@3x", "@2x", ""] {
            guard let url = bundle.url(forResource: "\(name)\(scale)", withExtension: "png") else { continue }
            guard let src = NSImage(contentsOf: url) else { continue }
            found = true
            for rep in src.representations {
                rep.size = NSSize(width: 14, height: 14)
                image.addRepresentation(rep)
            }
        }
        guard found else {
            return nil
        }
        image.size = NSSize(width: 14, height: 14)
        return image
    }

    private static func candidateDirs() -> [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources)
        }
        dirs.append(Bundle.main.bundleURL)
        if let executables = Bundle.main.executableURL?.deletingLastPathComponent() {
            dirs.append(executables)
        }
        return dirs
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let state = TimberState()
    private var refreshTimer: Timer?

    private let popoverWidth: CGFloat = 400
    private let backgroundRefreshInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only even as a raw binary (no .app bundle).
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Timber")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let hostingView = SizingHostingView(rootView: TimberPopover(state: state))
        let viewController = NSViewController()
        viewController.view = hostingView
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: popoverWidth, height: 160)
        hostingView.onLayout = { [weak popover, popoverWidth] size in
            guard let popover, popover.isShown, size.height > 0,
                  abs(popover.contentSize.height - size.height) > 0.5
            else { return }
            popover.contentSize = NSSize(width: popoverWidth, height: size.height)
        }
        self.popover = popover

        // Keep the list warm so the popover is ready on open: one load
        // now, then a quiet reload (filter/selection untouched) every
        // minute. The poll pauses while the popover is shown so rows never
        // shift under the cursor; opening the popover still does a full
        // refresh.
        state.refreshInBackground()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: backgroundRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.popover?.isShown != true else { return }
            state.refreshInBackground()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let secondary = NSApp.currentEvent.map { $0.type == .rightMouseUp } ?? false
        switch TimberModel.statusItemClickAction(isSecondaryClick: secondary) {
        case .showContextMenu:
            showContextMenu()
        case .togglePopover:
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Show the warmed cache instantly, then catch up quietly: the
            // background poll preserves selection by row id, so the list
            // never blanks out or visibly reloads on open.
            state.presentFromCache()
            state.refreshInBackground()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button, let popover else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit Timber",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}

// Note: there is deliberately no SwiftUI App scene here. The entry point
// is main.swift (plain AppKit lifecycle); a Settings scene would open a
// blank window at launch.

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
        .frame(width: 400)
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
                .truncationMode(.tail)
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
