---
name: Bug report
about: A window went to the wrong place, a shortcut didn't work, or something else broke
title: ""
labels: bug
---

**What you did** (the shortcut, menu item or `paneful` command):

**What you expected:**

**What happened instead:**

**macOS version** (Apple menu → About This Mac):

**Displays:** how many, and how they are arranged (side by side, one above the other, an iPad with Sidecar):

**The apps involved:**

**`paneful displays --json` and `paneful list --json`**, run right after it happened. They list your displays and the visible windows, including window titles: remove or replace any title you don't want to share.

```json
<!-- paste here -->
```

**If you used a command, its output with `--json`**, including the `differs` / `skipped` / `verified` fields:

```json
<!-- paste here -->
```

**Your config** (`~/.config/paneful/config.json`), if you changed it:

```json
<!-- paste here -->
```
