# AGENTS.md

Instructions for AI coding agents working in this repository. Humans are welcome to read it too.

## What this is

Fenping is a macOS menu bar app that moves and resizes windows with global hotkeys. It is intentionally small so that a person can fork it and have an agent reshape it into their own tool. Favor small, readable changes over abstractions.

- Language: Swift, compiled with `swiftc` directly. No Xcode project, no Swift Package, no third-party dependencies. Keep it that way.
- Minimum macOS: 13.
- UI language: Chinese. User-facing strings and code comments are in Chinese; keep new ones consistent unless the user asks to translate.

## Build, test, run

```bash
bash build.sh            # compile to build/Fenping.app and run the self-test
bash build.sh install    # also copy to ~/Applications and launch
bash build.sh snapshot   # re-render the welcome screens to docs/welcome-*.png
```

The self-test (`Fenping --selftest`) covers geometry, key parsing, config decoding and drag zones. It runs on every build and the build fails if it fails. Add a check there whenever you add an action, a config field, or a layout rule.

`Fenping --check <file>` validates a config file. Every file in `examples/` must pass it.

## What you cannot verify yourself

Moving real windows requires the Accessibility permission, which only the user can grant in System Settings. An ad-hoc signed rebuild invalidates the previous grant, so after `bash build.sh install` the user usually has to remove and re-add Fenping in the Accessibility list (or run `tccutil reset Accessibility local.fenping`). Tell the user this instead of claiming the change was tested end to end. Do not try to change that permission yourself.

What you can verify: the self-test, `--check`, and the welcome screen snapshots (open the PNGs in `docs/` and look at them after changing `Welcome.swift`).

Runtime log: `~/Library/Logs/Fenping.log`.

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
| `main.swift` | Entry point, `--selftest`, `--check`, `--snapshot`, and the `repoURL` constant |

## Conventions that matter

- **Coordinates.** Geometry and the AX API use a top-left origin with y pointing down. `NSScreen` uses a bottom-left origin. Convert with `flip(_:)` at the boundary and nowhere else.
- **Unit rects.** Positions are expressed as fractions of the screen's visible area (`0...1`), then turned into points by `screenRect(unit:visible:gap:)`. New positions should go through it so gaps keep working.
- **The config file is the single source of truth** (`~/.config/fenping/config.json`). Menu toggles write to it through `ConfigStore.update`. Do not add a second settings store.
- **Config must stay forgiving.** Every field is optional when decoding. A bad entry produces a warning from `Config.warnings()` and is skipped; it must never crash the app or block the rest of the config.
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
Edit `WindowManager.tileAll()`. The row shapes come from `TileConfig.rows(for:)` and `defaultTileRows(_:)`.

**Change the onboarding**
Edit `Welcome.swift`, then run `bash build.sh snapshot` and look at the PNGs.

## When you fork

Change `repoURL` in `Sources/main.swift` and the clone URL in `README.md` to the new repository. If you rename the app, also change the bundle identifier in `build.sh` and the config path in `Config.swift`.
