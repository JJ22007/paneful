# AGENTS.md

Instructions for AI coding agents working in this repository. Humans are welcome to read it too.

## What this is

Paneful is a macOS menu bar app that moves and resizes windows with global hotkeys. It is intentionally small so that a person can fork it and have an agent reshape it into their own tool. Favor small, readable changes over abstractions.

- Language: Swift, compiled with `swiftc` directly. No Xcode project, no Swift Package, no third-party dependencies. Keep it that way.
- Minimum macOS: 13.
- Language: English for the UI, code comments, commit messages and docs. `README.zh-CN.md` is a translation of the README; update it when the README changes in substance.

## Build, test, run

```bash
bash build.sh            # compile to build/Paneful.app and run the self-test
bash build.sh install    # also copy to ~/Applications and launch
bash build.sh snapshot   # re-render the welcome screens to docs/welcome-*.png
bash scripts/setup-signing.sh   # one-time: stable signing identity (user runs this)
```

The self-test (`Paneful --selftest`) covers geometry, key parsing, config decoding and drag zones. It runs on every build and the build fails if it fails. Add a check there whenever you add an action, a config field, or a layout rule.

`Paneful --check <file>` validates a config file. Every file in `examples/` must pass it.

`bash build.sh` already runs the self-test and checks every file in `examples/`, and stops with an error if either fails. When it prints `all tests passed` you don't need to run them again by hand.

To look at the welcome screens in another language without changing the system: `build/Paneful.app/Contents/MacOS/Paneful --snapshot /tmp/shots -AppleLanguages "(ja)"`.

The installed app also answers `paneful list | displays | tile | run | place | fullscreen | apply | save | restore | mcp | actions`, each with `--json` (see `Sources/CLI.swift`). With the app running and the permission granted, `paneful list` is a quick way to check real window positions after a change. Moves report the frame read back from macOS, so you can check a layout change against real windows; run `paneful save` first and `paneful restore` afterwards to leave the user's desktop as you found it.

## What you cannot verify yourself

Moving real windows requires the Accessibility permission, which only the user can grant in System Settings. The grant is tied to the code signature. With an ad-hoc signature every rebuild invalidates it, while the switch in System Settings can still look on. `scripts/setup-signing.sh` fixes this for good by creating a local self-signed identity that `build.sh` then uses automatically; it writes to the user's login keychain, so ask the user to run it rather than running it yourself. Without it, after `bash build.sh install` the user has to remove and re-add Paneful in the Accessibility list (or run `tccutil reset Accessibility io.github.paneful`). Say this plainly instead of claiming a change was tested end to end, and never try to grant the permission yourself.

What you can verify: the self-test, `--check`, and the welcome screen snapshots (open the PNGs in `docs/` and look at them after changing `Welcome.swift`).

Runtime log: `~/Library/Logs/Paneful.log`.

## Layout of the code

All sources are in `Sources/`.

| File | Responsibility |
|---|---|
| `Actions.swift` | `Action` enum: built-in actions, titles, default shortcuts, menu grouping, icon shapes |
| `Geometry.swift` | Pure functions: unit rects, gaps, tiling rows, cross-display remap, coordinate flip |
| `WindowManager.swift` | Picks the window and screen, applies a target frame, remembers frames for restore |
| `Accessibility.swift` | Thin wrapper over the AX API; the only code that needs the permission |
| `Config.swift` | `Config` model, defaults, validation warnings, `ConfigStore` (load, save, hot reload) |
| `Keys.swift` | `KeyCombo.parse("ctrl+alt+left")` and Carbon global hotkey registration |
| `DragSnap.swift` | Drag-to-edge snapping and its preview overlay |
| `Glyph.swift` | The small layout icons used in the menu and the welcome screens |
| `App.swift` | `AppDelegate`: status item, menu, applying config to hotkeys |
| `Welcome.swift` | SwiftUI onboarding: intro, permission, shortcuts, customize |
| `CLI.swift` | The `paneful` command line client and the in-app server it talks to (distributed notification in with a per-launch token, reply file out), read-back reporting, `apply`, save and restore |
| `MCP.swift` | `paneful mcp`: an MCP server over stdio whose tools forward to the same CLI commands. Tool results are errors unless the read-back verified them |
| `MenuBarIcon.swift` | The menu bar icon (Lucide `layout-panel-left`), drawn in code as a template image |
| `main.swift` | Entry point, `--selftest`, `--check`, `--snapshot`, and the `repoURL` constant |

## Conventions that matter

- **Coordinates.** Geometry and the AX API use a top-left origin with y pointing down. `NSScreen` uses a bottom-left origin. Convert with `flip(_:)` at the boundary and nowhere else.
- **Unit rects.** Positions are expressed as fractions of the screen's visible area (`0...1`), then turned into points by `screenRect(unit:visible:gap:)`. New positions should go through it so gaps keep working.
- **The config file is the single source of truth** (`~/.config/paneful/config.json`). Menu toggles write to it through `ConfigStore.update`. Do not add a second settings store.
- **Config must stay forgiving.** Every field is optional when decoding. A bad entry produces a warning from `Config.warnings()` and is skipped; it must never crash the app or block the rest of the config.
- **Left/right half across displays.** A repeated press cycles widths. With `crossDisplays` on and more than one display it moves the window to the next display instead (`neighborDisplay` in `Geometry.swift`, used in `WindowManager.perform`).
- **The CLI channel is guarded.** Requests must carry the token from `CLI.tokenURL` and reply into the temp folder (`CLI.isSafeReplyPath`). Keep both checks if you change the protocol, and never let a request make the app read or write a path it names; file I/O for `save` and `restore` happens in the client.
- **Messages people see when something is wrong** (permission, taken shortcuts) go through `L(english, chinese)` in `App.swift`. The rest of the UI is English.
- **Hotkeys are re-registered from scratch** on every config change in `AppDelegate.applyConfig()`.

## Common tasks

**Add a built-in action**
1. Add a case to `Action` with a title and a default shortcut, and put it in `Action.groups`.
2. Give it a position in `unitRect(for:)` in `Geometry.swift`. If it is not a fixed position, handle it in `WindowManager.perform(_:on:screen:)`.
3. Add a self-test line. Update the shortcut table in `README.md`.

**Add a config option**
1. Add the field to `Config` with a default, decode it with `decodeIfPresent`, and validate it in `warnings()`.
2. Read it where it is used via `ConfigStore.shared.config`.
3. Document it in the README field table and add or update a file in `examples/`.

**Change how "tile all" assigns windows**
Edit `WindowManager.tileAll()`. The shapes come from `tileShape(_:rows:)` in `Geometry.swift` (a tree of `Tile` slots; the user's `tile.rows` override it), and `tileFrames` lays them out. Many apps have a minimum window size: `tileAll()` reads the windows back and re-lays the shape with those minimums (`shareOut`), so keep columns whole where you can, since a wide window then widens its column instead of overlapping a neighbor. If the user can run it, ask them to try `paneful save && paneful tile` and check the lines marked `differs`, then `paneful restore`.

**See what other agents did**
[`docs/recipes/`](docs/recipes/README.md) has six one-sentence changes made by an agent, with their diffs and what happened on real windows.

**Change the onboarding**
Edit `Welcome.swift`, then run `bash build.sh snapshot` and look at the PNGs.

## When you fork

Change `repoURL` in `Sources/main.swift` and the clone URL in both READMEs to the new repository. If you rename the app, also change the bundle identifier and app name in `build.sh`, the identity name in `scripts/setup-signing.sh`, and the config path in `Config.swift`.
