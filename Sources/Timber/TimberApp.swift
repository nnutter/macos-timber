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

/// Popover width bounds: the popover grows to fit long
/// `worktree@repo` names, clamped so short lists stay usable and very
/// long names truncate (from the middle) instead of stretching across
/// the screen. Bounds live in TimberModel so the math stays tested;
/// row widths inside the ScrollView do not reach the hosting view's
/// fitting size, so the width is measured from the longest row text
/// (including the icon cluster chrome) instead of the layout size.
enum PopoverSizing {
    static var minWidth: CGFloat {
        CGFloat(TimberModel.popoverMinWidth)
    }

    static var maxWidth: CGFloat {
        CGFloat(TimberModel.popoverMaxWidth)
    }

    /// Display string for a row, mirroring TimberRow's text.
    static func displayString(for item: TimberItem) -> String {
        (item.kind == .create ? "+ " : "") + item.value
    }

    static func textWidth(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
    }

    static func width(for items: [TimberItem]) -> CGFloat {
        CGFloat(TimberModel.popoverWidth(textWidths: items.map { Double(textWidth(displayString(for: $0))) }))
    }
}

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
        popover.contentSize = NSSize(width: PopoverSizing.minWidth, height: 160)
        let state = state
        hostingView.onLayout = { [weak popover, state] size in
            guard let popover, popover.isShown, size.height > 0 else { return }
            // Height follows the SwiftUI layout; width follows the
            // longest measured row (ScrollView rows never widen the
            // fitting size, so fittingSize.width stays near the minimum
            // and truncates rows early if trusted).
            let width = PopoverSizing.width(for: state.items)
            guard abs(popover.contentSize.height - size.height) > 0.5
                || abs(popover.contentSize.width - width) > 0.5
            else { return }
            popover.contentSize = NSSize(width: width, height: size.height)
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
            // Pre-size to the cached rows so the first frame never
            // flashes narrow; onLayout keeps height (and width, as the
            // filter narrows the list) in sync afterwards.
            popover.contentSize.width = PopoverSizing.width(for: state.items)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button, let popover else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        let loginItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleOpenAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = TimberLoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Timber",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        do {
            try TimberLoginItem.setEnabled(enabled)
            sender.state = enabled ? .on : .off
        } catch {
            TimberCommand.notify(
                subject: enabled ? "open at login" : "remove from login",
                detail: error.localizedDescription,
                failure: true
            )
        }
    }
}

// Note: there is deliberately no SwiftUI App scene here. The entry point
// is main.swift (plain AppKit lifecycle); a Settings scene would open a
// blank window at launch.
