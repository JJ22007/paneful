<h1 align="center">Paneful</h1>

<p align="center">
  <b>A small macOS window manager for you and your coding agent to fork and reshape.</b><br>
  about 2,100 lines of Swift, no dependencies, one <code>swiftc</code> command to build. Comes with a CLI your agent can use to arrange your windows.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="#which-one-should-you-use">Which one?</a> ·
  <a href="#install">Install</a> ·
  <a href="#make-it-yours">Customize</a> ·
  <a href="#let-an-agent-drive">Agents</a> ·
  <a href="#build-your-own">Build your own</a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="100%" alt="An AI agent tidies a messy desktop with one sentence">
</p>
<p align="center"><sub>One sentence to Claude Code, and a messy desktop snaps into place. Real recording; the few seconds the agent spends thinking are sped up.</sub></p>

Paneful is a menu bar app that moves windows with the keyboard, or on an agent's say-so. It is not trying to be a better Rectangle. It is trying to be small enough that you, or your coding agent, can read all of it and turn it into your own tool: 13 files and about 2,100 lines of Swift, no dependencies, no Xcode project, and a self-test that runs on every build.

## Which one should you use?

Paneful is the right pick for few people, so here is the honest version.

| If you want… | Use |
|---|---|
| Halves and quarters, nothing else | What macOS already has: drag to a screen edge, or the green button's menu |
| A polished window tool that just works | [Rectangle](https://github.com/rxhanson/Rectangle): free, many more positions, a shortcut recorder, signed releases |
| Automatic i3 / xmonad style tiling | [AeroSpace](https://github.com/nikitabobko/AeroSpace), [Amethyst](https://github.com/ianyh/Amethyst) or [yabai](https://github.com/asmvik/yabai) |
| An agent toolkit with MCP, workspaces, screenshots and OCR | [Plonk](https://github.com/ostapondo/Plonk) |
| A window manager small enough to make entirely your own, with your agent doing the edits | Paneful |

What Paneful offers in exchange: the source is about 105 KB, a small fraction of the tools above, so an agent can read it in one go. [`AGENTS.md`](AGENTS.md) tells the agent where things live and what it can't check by itself. The `paneful` command needs no Node, MCP setup or Lua: if your agent can run a shell command, it can list and place windows.

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
| `⌃⌥⌘→` `⌃⌥⌘←` | Walk right, walk left: one half at a time, across every display | `nextDisplay` `prevDisplay` |
| `⌃⌥⌘↑` | Jump to the next display: focus its front window and move the pointer there. Windows stay put | `focusNextDisplay` |

Press left half or right half again to cycle its width: 1/2 → 2/3 → 1/3.

**Walking across displays.** `⌃⌥⌘→` moves a window one half to the right each time: left half, right half, then the left half of the next display, then its right half, and so on. `⌃⌥⌘←` walks back. Displays are taken left to right and wrap around, so it also works when one sits above the other. If you would rather do this with the plain half keys and give up width cycling, set `crossDisplays` to `true`.

**Jumping between displays.** `⌃⌥⌘↑` moves the focus, not a window: it activates the front window on the next display and puts the pointer on it, so the next shortcut works there. macOS's own `⌃←` / `⌃→` then switch Spaces on that display. With two displays the key toggles between them.

## Make it yours

The config lives at `~/.config/paneful/config.json`. Open it from the menu bar with **Edit Config File…**. Write only what you want to change; everything else keeps its default.

```json
{
  "gap": 8,
  "dragSnap": false,
  "shortcuts": {
    "maximize": "ctrl+alt+space",
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
| `crossDisplays` | Off by default. When on and more than one display is connected, pressing left or right half again moves the window to the next display instead of cycling widths. |
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
| `paneful list` | List every window: app, title, display, and position as screen fractions |
| `paneful displays` | List displays, numbered left to right |
| `paneful tile` | Tile all windows into a grid |
| `paneful place 0 0 0.6 1 --app Safari` | Put a window anywhere. Numbers are `x y w h` from 0 to 1 |
| `paneful run leftHalf --title notes --display 2` | Run any built-in action on a specific window, optionally on another display |
| `paneful fullscreen off --app Keynote` | Enter or leave native fullscreen |
| `paneful apply layout.json` | Place several windows at once, by app or title (format below) |
| `paneful save` / `paneful restore` | Remember where every window is, and put them all back |
| `paneful mcp` | The same commands as an MCP server, for agents and tools that speak MCP |
| `paneful actions` | List the action names |

`--app` matches the app name or bundle id, `--title` the window title, both by case-insensitive substring. Without them a command applies to the focused window. Chain commands with `&&` to build a whole layout in one go.

**Checked, not assumed.** After every move Paneful reads each window's frame back from macOS and reports where it really is. Some apps refuse a size (a minimum width, say); those lines say `differs` and show what was asked and what the app accepted, so an agent can tell the user instead of claiming success.

**Undo.** `paneful save` writes every window's position to `~/.config/paneful/layout.json` (or a file you name), and `paneful restore` puts them back and reports any it couldn't find. Have the agent save first and you can always get your desktop back.

**Whole layouts.** `paneful apply` takes a file (or `-` for stdin) listing windows and where they go. Each entry takes the first matching window not used yet; `display` is optional:

```json
[{"app": "Safari", "x": 0, "y": 0, "w": 0.6, "h": 1},
 {"app": "Notes", "title": "todo", "x": 0.6, "y": 0, "w": 0.4, "h": 1, "display": 2}]
```

**For programs.** Add `--json` to any command. `list --json` gives the app, bundle id, title, display, screen fractions and the frame in points; moves add the requested frame, `matchesTarget`, any `skipped` windows and an overall `verified`. Exit status: 0 done and verified, 3 done but not verified (a window differs or was skipped), 1 error, 2 Paneful isn't running.

**MCP.** `paneful mcp` serves `list_windows`, `list_displays`, `apply_layout`, `tile_all`, `save_layout` and `restore_layout` over stdio. Each call goes through the same channel and the same read-back as the command line, and a result is marked as an error unless it was verified. Add it to an MCP client as the command `paneful` with the argument `mcp`.

To get the result in the recording above, give your agent a few lines of context (a `CLAUDE.md`, a system prompt, or just paste it) and then talk to it normally:

```markdown
You arrange windows on this Mac with the `paneful` command line tool.
Run `paneful help` to see the commands. Run `paneful save` before you move anything.
Check the output: if a line says "differs", tell me. Act right away, then reply in one short sentence.
```

```text
> My desktop is a mess. Keep this terminal on the left third and arrange the other windows in a neat grid on the right.
```

The command line tool talks to the running app, so Paneful has to be open and have the Accessibility permission. The agent itself needs no special permission.

**Trust model.** The command reaches the app through a macOS distributed notification, which any process in your login session can send. Each request must carry a random token that Paneful writes at launch to `~/Library/Application Support/Paneful/cli-token`, readable only by your user. Sandboxed apps can't read it, so they can't use Paneful to list your window titles or move windows. Unsandboxed programs you run can, but they could already read your files and do far more. Replies are only written into your own temporary folder. If you'd rather have no channel at all, remove `CLI.startServer()` in your fork.

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

See [`docs/recipes/`](docs/recipes/README.md) for six of these done by Claude Code from a single sentence, with the full diffs and what happened on real windows, including the one that didn't quite work.

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
| [`MenuBarIcon.swift`](Sources/MenuBarIcon.swift) | The menu bar icon, drawn in code | change the icon |
| [`Accessibility.swift`](Sources/Accessibility.swift) | System calls that read and move windows | rarely |

After changing the guide, run `bash build.sh snapshot` to re-render each step into `docs/`.

## Limitations

- **It can't move windows between Spaces** or create a Space. macOS has no public API for that.
- Fullscreen and minimized windows, and windows on other Spaces, are left out of "tile all".
- Some apps enforce a minimum window size, so a window can end up larger than its cell.
- Shortcuts are set in the config file. There is no shortcut recorder, on purpose: the config file is the only source of settings, which keeps the code small.
- Errors and the permission prompts follow your system language (English or Simplified Chinese); the rest of the interface is English.
- No downloadable release yet. You build it from source, and without `scripts/setup-signing.sh` every rebuild loses the Accessibility permission.
- Tested by the author on Apple silicon with macOS 27 and two displays. Intel Macs and older macOS versions should work but haven't been tried.

## Credits

The default shortcuts and overall feel follow [Rectangle](https://github.com/rxhanson/Rectangle), so your muscle memory carries over. If you want a mature tool that just works, use Rectangle; it's excellent. Paneful has a different goal: to be small enough that you can make it entirely your own.

The menu bar icon is from [Lucide](https://lucide.dev) (ISC, see [LICENSES/lucide.txt](LICENSES/lucide.txt)).

## License

[MIT](LICENSE)
