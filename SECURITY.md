# Security and privacy

## Reporting a problem

Use **Report a vulnerability** on the repository's Security tab. It is private to the maintainer. If you can't use it, open an issue that says there is a security problem, without the details, and you will be contacted.

## What Paneful can change

- **The position and size of other apps' windows**, and whether a window is in native fullscreen.
- **Which window is in front**, and where the pointer is, but only for Jump to Next Display (`⌃⌥⌘↑`), which brings the front window on the other display forward and moves the pointer onto it.
- **Its own files** (below), and its login item if you switch on Launch at Login.

It never types, clicks, closes windows or reads what is inside them.

## What it reads, and where that goes

- **Window frames, window titles and app names** of the windows on screen, through the Accessibility API and the window server's window list. Titles are used to pick windows (`--title`, `apply`, `restore`) and are shown in `paneful list`.
- **Mouse button events**, only while `dragSnap` is on in the config, to see where a dragged window is dropped. Keystrokes are never read; shortcuts are registered with the system as hot keys.
- **Nothing leaves your Mac.** Paneful makes no network requests. The two links in its menu and welcome screens open the project page in your browser.

## Permissions

- **Accessibility** is the only permission. macOS ties it to the app's signature, which is why `scripts/setup-signing.sh` creates a local signing identity: a rebuild keeps the grant instead of asking again.
- **No screen recording, no camera or microphone, no network, no sudo.** `build.sh install` installs for the current user only, into `~/Applications`.

## Files it writes

| File | What it holds |
|---|---|
| `~/.config/paneful/config.json` | Your settings and shortcuts. The app writes it when you change a setting from its menu or welcome screens, and picks up your own edits. |
| `~/.config/paneful/layout.json`, or the file you name | Written by `paneful save`: every window's app, bundle id, title and frame. Delete it when you no longer need it. |
| `~/Library/Application Support/Paneful/cli-token` | A random token, new at every launch (below). The folder is mode 0700, the file 0600. |
| Paneful's preferences | Only whether the welcome guide was shown. |

## The `paneful` command and `paneful mcp`

The command reaches the running app through a macOS distributed notification. Every process in your login session can post one, sandboxed apps included. So:

- Each request must carry the token from `cli-token`, readable only by you. Sandboxed apps can't read it, so they can't use Paneful to list your window titles or move your windows. Requests without the right token are ignored.
- Replies are written only to `paneful-<UUID>.reply` files directly in your own temporary folder. A request can't make the app read or write any other path; `save` and `restore` read and write their layout files in the command's own process, not in the app.
- `paneful mcp` is the same command speaking MCP over stdin and stdout. It opens no port and is reachable only by the program that started it (your agent, or a tool such as [Knobs](https://github.com/JJ22007/knobs)). Every tool call goes through the same token and the same checks.

A program running as you, outside a sandbox, can still read the token and move your windows. It could already read your files and do far more, so the token is not meant to stop it. If you would rather have no command channel at all, remove `CLI.startServer()` in your copy.

## Downloads

Building from source is the way to install today (see the README). If a release `.zip` is published, it will say how it was signed and include a `SHA256SUMS.txt`; in the folder that holds both files, run `shasum -a 256 -c SHA256SUMS.txt`. A matching checksum shows the file is the one the release built. It is not a signature: anyone who can change the release can change both files.
