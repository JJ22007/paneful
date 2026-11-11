<h1 align="center">Paneful</h1>

<p align="center">
  <b>Window tiling for macOS that isn't painful.</b><br>
  Small enough to read in one sitting. Built to be forked and reshaped.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="#install">Install</a> ·
  <a href="#make-it-yours">Customize</a> ·
  <a href="#let-an-agent-drive">Agents</a> ·
  <a href="#build-your-own">Build your own</a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="100%" alt="An AI agent tidies a messy desktop with one sentence">
</p>
<p align="center"><sub>One sentence to Claude Code, and a messy desktop snaps into place. Real recording; the few seconds the agent spends thinking are sped up.</sub></p>

Paneful is a menu bar app that snaps windows into place with the keyboard, or on an agent's say-so. It is about 1,700 lines of Swift with no dependencies and no Xcode project. Everything you might want to change sits in one JSON file, and anything the file can't do is a short edit away, by you or by your AI coding agent.

## Features

- **Keyboard tiling.** Halves, quarters, thirds, two-thirds, maximize, center, restore, and move between displays. The defaults match [Rectangle](https://github.com/rxhanson/Rectangle), so your muscle memory still works.
- **Tile everything.** Press `⌃⌥A` and every window on the desktop spreads into a grid: two side by side, three in columns, four in quarters, five as three over two, six as 3×2. The rules are yours to change.
- **Custom positions.** Describe any spot as fractions of the screen and bind it to a key.
- **Agent-ready.** A `paneful` command lets scripts and AI agents list, place and tile windows, so "put my editor on the left and stack the rest" just works.
- **One config file, hot reloaded.** Save the file and the change applies within a second or two. Mistakes show up in the menu instead of breaking the app.
- **Drag to snap.** Optional edge snapping with a live preview.
- **A proper first run.** A four-step guide handles the permission, teaches the shortcuts, and shows how to customize.

## Install

Requires macOS 13 or later and the Swift compiler. If you have never installed it, run `xcode-select --install` first.

```bash
git clone https://github.com/JJ22007/paneful.git
cd paneful
bash build.sh install
```

This compiles the app, runs the self-test, installs `Paneful.app` into `~/Applications` and launches it. The welcome guide then walks you through switching Paneful on under System Settings → Privacy & Security → Accessibility.

### Planning to rebuild? Run this once

macOS ties the Accessibility permission to the app's code signature. A plain source build is ad-hoc signed, so every rebuild looks like a new app: the permission stops working, even though the switch in System Settings may still look on.

```bash
bash scripts/setup-signing.sh
```

The script creates a self-signed certificate in your login keychain, used only to sign your own builds, then rebuilds and installs. Grant the permission one more time and it survives every rebuild after that. `build.sh` picks the certificate up automatically. If you have an Apple Developer ID, use `SIGN_ID="Developer ID Application: You" bash build.sh install` instead.

## Shortcuts

| Shortcut | Action | Name in config |
|---|---|---|
| `⌃⌥A` | Tile all windows | `tileAll` |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Left, right, top, bottom half | `leftHalf` `rightHalf` `topHalf` `bottomHalf` |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | Top left, top right, bottom left, bottom right | `topLeft` `topRight` `bottomLeft` `bottomRight` |
| `⌃⌥D` `⌃⌥F` `⌃⌥G` | First, center, last third | `firstThird` `centerThird` `lastThird` |
| `⌃⌥E` `⌃⌥T` | First, last two thirds | `firstTwoThirds` `lastTwoThirds` |
| `⌃⌥↩` | Maximize | `maximize` |
| `⌃⌥M` | Almost maximize (90%) | `almostMaximize` |
| `⌃⌥C` | Center | `center` |
| `⌃⌥⌫` | Restore the previous frame | `restore` |
| `⌃⌥⌘→` `⌃⌥⌘←` | Next, previous display | `nextDisplay` `prevDisplay` |

Press left half or right half again to cycle its width: 1/2 → 2/3 → 1/3.

## Make it yours

The config lives at `~/.config/paneful/config.json`. Open it from the menu bar with **Edit Config File…**. Write only what you want to change; everything else keeps its default.

```json
{
  "gap": 8,
  "dragSnap": false,
  "shortcuts": {
    "maximize": "ctrl+alt+m",
    "center": ""
  },
  "custom": [
    { "name": "Code", "key": "ctrl+alt+1", "x": 0, "y": 0, "w": 0.62, "h": 1 },
    { "name": "Docs", "key": "ctrl+alt+2", "x": 0.62, "y": 0, "w": 0.38, "h": 1 }
  ],
  "tile": {
    "max": 6,
    "rows": { "5": [2, 3] }
  }
}
```

| Field | Meaning |
|---|---|
| `gap` | Space between windows and around the screen edge, in points. |
| `dragSnap` | Snap windows dragged to a screen edge. Turn off macOS's own edge tiling first (System Settings → Desktop & Dock), or you will see two previews. |
| `shortcuts` | Action name → shortcut. Use `""` to remove a shortcut. |
| `custom` | Your own positions. `x`, `y`, `w`, `h` are fractions of the screen from 0 to 1, with the origin at the top left. `key` is optional. |
| `tile.max` | The most windows "tile all" will arrange. The rest stay put; the most recently used win. |
| `tile.rows` | Window count → windows per row. `"5": [2, 3]` puts two on top and three below. Unlisted counts use the default rule. |

**Shortcut syntax.** Modifiers plus one key, joined with `+`, case-insensitive. Modifiers are `ctrl`, `alt`, `shift`, `cmd`. Keys are letters, digits, `left` `right` `up` `down`, `return`, `delete`, `space`, `tab`, `escape`, `f1`–`f12`, and common punctuation.

**When you get it wrong.** The menu shows "Config Problems" with the exact entry at fault. That entry is skipped and the rest keeps working. You can also check a file from the terminal:

```bash
~/Applications/Paneful.app/Contents/MacOS/Paneful --check ~/.config/paneful/config.json
```

### Examples

Copy from [`examples/`](examples):

| File | For |
|---|---|
| [`minimal.json`](examples/minimal.json) | Just a little breathing room between windows |
| [`coding.json`](examples/coding.json) | A wide editor with terminal and browser stacked on the right |
| [`ultrawide.json`](examples/ultrawide.json) | Ultrawide monitors: a center stage, two sidebars, single-row tiling |
| [`vim-keys.json`](examples/vim-keys.json) | H J K L instead of the arrow keys |
| [`four-only.json`](examples/four-only.json) | Tile at most four windows and leave the rest alone |

<p align="center">
  <img src="docs/welcome-1.png" width="49%" alt="Welcome screen">
  <img src="docs/welcome-4.png" width="49%" alt="Customize step of the welcome guide">
</p>

## Let an agent drive

Paneful ships with a command line interface. Anything that can run a shell command can arrange your windows: a script, a launcher, or an AI agent.

```bash
# once: put the command on your PATH
ln -s ~/Applications/Paneful.app/Contents/MacOS/Paneful /usr/local/bin/paneful
```

| Command | What it does |
|---|---|
| `paneful list` | List every window: app, title, and position as screen fractions |
| `paneful tile` | Tile all windows into a grid |
| `paneful place 0 0 0.6 1 --app Safari` | Put a window anywhere. Numbers are `x y w h` from 0 to 1 |
| `paneful run leftHalf --title notes` | Run any built-in action on a specific window |
| `paneful fullscreen off --app Keynote` | Enter or leave native fullscreen |
| `paneful actions` | List the action names |

`--app` matches the app name or bundle id, `--title` the window title, both by case-insensitive substring. Without them a command applies to the focused window. Chain commands with `&&` to build a whole layout in one go.

To get the result in the recording above, give your agent a few lines of context (a `CLAUDE.md`, a system prompt, or just paste it) and then talk to it normally:

```markdown
You arrange windows on this Mac with the `paneful` command line tool.
Run `paneful help` to see the commands. Act right away, then reply in one short sentence.
```

```text
> My desktop is a mess. Keep this terminal on the left third and arrange the other windows in a neat grid on the right.
```

The command line tool talks to the running app, so Paneful has to be open and have the Accessibility permission. The agent itself needs no special permission.

## Build your own

When the config isn't enough, change the code. The project is written to be easy for people and coding agents to read.

1. **Fork** the repo and clone your fork.
2. Open it with your coding agent (Claude Code, Cursor, Codex, and so on). [`AGENTS.md`](AGENTS.md) already explains the layout, how to build, and how to verify changes.
3. **Say what you want in plain words.** For example:
   - "Add a shortcut that centers the window at 60% width and cycles 60% / 80% / 100% when pressed again."
   - "When tiling, give the focused window the left half and stack the others on the right."
   - "Dragging to the bottom edge should snap to thirds."
   - "Translate the interface to Japanese."
4. Run `bash build.sh install` and try it.

Prefer to do it by hand? Each file has one job:

| File | Job | Look here to… |
|---|---|---|
| [`Actions.swift`](Sources/Actions.swift) | Built-in actions, titles, default shortcuts | add an action |
| [`Geometry.swift`](Sources/Geometry.swift) | Position math, all pure functions | change positions or tiling rules |
| [`WindowManager.swift`](Sources/WindowManager.swift) | Decides which window goes where | change how "tile all" assigns windows |
| [`Config.swift`](Sources/Config.swift) | Reading, writing and validating the config | add a config option |
| [`Keys.swift`](Sources/Keys.swift) | Shortcut parsing and global hotkeys | support more keys |
| [`DragSnap.swift`](Sources/DragSnap.swift) | Drag-to-edge snapping | change the snap zones |
| [`App.swift`](Sources/App.swift) | Menu bar icon and menu | change the menu |
| [`Welcome.swift`](Sources/Welcome.swift) | First-run guide (SwiftUI) | change the onboarding |
| [`CLI.swift`](Sources/CLI.swift) | The `paneful` command and its server inside the app | add a command |
| [`Accessibility.swift`](Sources/Accessibility.swift) | System calls that read and move windows | rarely |

After changing the guide, run `bash build.sh snapshot` to re-render each step into `docs/`.

## Limitations

- **It can't move windows between Spaces** or create a Space. macOS has no public API for that.
- Fullscreen and minimized windows, and windows on other Spaces, are left out of "tile all".
- Some apps enforce a minimum window size, so a window can end up larger than its cell.
- Shortcuts are set in the config file. There is no shortcut recorder.

## Credits

The shortcuts and overall feel follow [Rectangle](https://github.com/rxhanson/Rectangle). If you want a mature tiling tool that just works, use it; it's excellent. Paneful has a different goal: to be small enough that you can make it entirely your own.

## License

[MIT](LICENSE)
