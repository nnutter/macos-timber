# Timber — macOS menubar frontend to `timber`

A macOS menubar port of [omarchy-timber](https://github.com/nnutter/omarchy-timber)
(the QuickShell bar widget): a timber icon in the menubar plus a popover for
managed Git worktrees. Requires the `timber` CLI and an Xcode toolchain.

## Behavior (mirrors Panel.qml)

- Popover lists existing worktrees as `name@repo` rows, with a fuzzy filter
  field (`type worktree@repo`). `@` narrows by repo, e.g. `f@scribble`.
- Typing a qualified `name@repo` that does not exist yet offers a `+` row
  to create it (`timber create --no-herdr`), then opens it in Zed.
- Row click or Return opens the worktree in Zed (`zed --new`).
- Selected rows show Zed / Herdr / delete buttons. Herdr runs
  `timber herdr space --new` (or creates with `--herdr`) and posts a
  notification instead of opening Zed.
- Delete is two-phase: first click arms (red), second click runs
  `timber remove`. Any list change or selection move disarms.
- `+` header button opens a `timber repo add <url> [--name]` form.
- Failures post a macOS notification; never silently.
- Keyboard: Up/Down move, Return activates, Esc closes form / clears
  filter, Ctrl+U clears.
- Right-click (or Ctrl-click) the menubar icon for a Quit menu;
  left-click toggles the popover.

Notes on parity: enumeration is implemented natively with FileManager
(`timber repo list -q` plus a worktree-root scan) instead of the bash +
globstar script, since macOS ships bash 3.2. `timber repo add` here has no
`--alias` flag, so the form has URL + Name only.

## Layout

- `Sources/Timber/TimberApp.swift` — AppKit status item
  (left-click popover, right-click Quit menu), popover UI, action state.
- `Sources/Timber/main.swift` — plain AppKit entry point (no
  SwiftUI App scene, so no stray windows).
- `Sources/Timber/TimberCommand.swift` — `timber`/`zed`
  processes, enumeration, notifications.
- `Sources/Timber/Resources/` — Zed/Herdr action icons,
  rasterized from upstream `zed.svg`/`herdr.svg` (originals kept in
  `Artwork/`; the Herdr glyph was stripped of its light-mode background
  and whitened so both render as monochrome template images).
- `Sources/TimberModel/TimberModel.swift` — pure filter/argv logic ported
  from `TimberModel.js`, UI-independent.
- `Tests/TimberModelTests/` — unit tests for the model.

## Build & run

Your `xcode-select` may point at the Command Line Tools; the mise tasks
pin `DEVELOPER_DIR` to Xcode explicitly (or run
`sudo xcode-select -s /Applications/Xcode.app` once).

```sh
mise run      # builds dist/Timber.app and opens it (recommended)
mise test     # swift test (TimberModel suite)
mise lint     # SwiftLint (strict) + SwiftFormat check
mise format   # format Sources and Tests in place
```

`mise run` ships a real `.app` bundle (with `LSUIElement`, so no Dock
icon). That also matters for notifications: `UNUserNotificationCenter`
traps in a raw binary, so the app posts native notifications only from
the bundle and falls back to `osascript display notification` otherwise
(e.g. `swift run Timber`).

## Install a release download

Release zips carry a universal (`arm64` + `x86_64`) build with an
ad-hoc signature (no notarization). On first launch Gatekeeper will
refuse a plain double-click; instead right-click (or Ctrl-click)
`Timber.app` → Open → Open, or clear quarantine once:

```sh
xattr -d com.apple.quarantine Timber.app  # path to your copy
```
