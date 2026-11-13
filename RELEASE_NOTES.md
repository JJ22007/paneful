## Install

Paneful is meant to be built from source, so you (or your coding agent) can change it:

```bash
git clone https://github.com/JJ22007/paneful.git && cd paneful
bash scripts/setup-signing.sh   # once: rebuilds keep the Accessibility permission
bash build.sh install
```

Or download **Paneful-universal.zip**, unzip it, and move **Paneful.app** into Applications.

- macOS 13 or later, Apple silicon or Intel.
- Not notarized by Apple. If the first launch is blocked, choose **Open Anyway** under System Settings → Privacy & Security.
- Paneful needs the Accessibility permission. The download is ad-hoc signed, so macOS asks for the permission again after each update. Building from source with `scripts/setup-signing.sh` avoids that.
- Check the download: `shasum -a 256 -c SHA256SUMS.txt` should print `Paneful-universal.zip: OK`.

## 0.1.0

The first release. Paneful is a small keyboard window manager for macOS that you, or a coding agent, can read in one sitting and reshape.

- **Keyboard tiling** with Rectangle-compatible shortcuts: halves (press again for 2/3 and 1/3), quarters, thirds, maximize, center, restore.
- **Several displays.** `⌃⌥⌘←/→` walks a window half by half across every display. `⌃⌥⌘↑` moves the focus to the next display without moving any window.
- **Tile all (`⌃⌥A`) that respects apps.** Windows that won't shrink below a minimum get the room they need, fixed-width windows such as System Settings leave no gap, and nothing hangs off the screen. Two or three windows sit side by side, four in a grid, five in a grid plus a sidebar; choose another layout with `tile.shapes`.
- **A command line and an MCP server for agents.** `paneful list`, `place`, `run`, `apply` (a whole layout from JSON), `save` and `restore`. Every move is read back from macOS: results say `verified`, or which window differs and why. `paneful mcp` offers the same over MCP.
- **Works with Knobs and Overbright.** A [Knobs](https://github.com/JJ22007/knobs) profile can arrange windows, change macOS settings and set brightness together, and one `knobs undo` restores all three.
- **Recipes.** Six one-sentence changes made by a coding agent on a fresh clone, with every diff and what went wrong: `docs/recipes/`.
- **Security.** The command channel needs a per-launch token only you can read. No network access. See `SECURITY.md`.

Checked on one Mac (Apple silicon, macOS 27.2) with a built-in display and an iPad as a second display. Not yet tried on macOS 13 itself, on an Intel Mac, or with two external monitors; reports are welcome.
