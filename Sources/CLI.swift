// Command line interface, so scripts and AI agents can drive Paneful.
// Run `paneful help` for the commands.
//
// The command line process has no Accessibility permission of its own. It
// sends the request to the running app through a distributed notification,
// and the app writes the reply to a temporary file.
//
// Every request carries a token that the app writes to a file only your user
// can read (see `tokenURL`). Sandboxed apps can't read that file, so they
// can't use Paneful to read window titles or move windows. Unsandboxed
// programs running as you can; they could do far more than that anyway.

import AppKit
import ApplicationServices
import Security

enum CLI {
    static let commands: Set<String> = ["list", "displays", "tile", "run", "place", "fullscreen", "apply", "save", "restore", "mcp", "actions", "help", "--help", "-h"]
    static let channel = Notification.Name("io.github.paneful.command")
    static let tokenURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Paneful/cli-token")
    static let defaultLayoutURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/paneful/layout.json")

    static let usage = """
    paneful: drive the Paneful window manager from scripts and agents.

      paneful list                                 list windows, front to back
      paneful displays                             list displays, numbered left to right
      paneful tile                                 tile every window into a grid
      paneful run <action> [--app A] [--title T] [--display N]
                                                   run a built-in action
      paneful place <x> <y> <w> <h> [--app A] [--title T] [--display N]
                                                   put a window at a position
      paneful fullscreen <on|off> --app A          enter or leave native fullscreen
      paneful apply <file|->                       place several windows at once (see below)
      paneful save [file]                          save where every window is
      paneful restore [file]                       put every saved window back
      paneful actions                              list the action names
      paneful mcp                                  serve the same commands as MCP tools over stdio

    Positions are fractions of the screen from 0 to 1, origin at the top left:
    "place 0 0 0.6 1" is the left 60%, "place 0.6 0.5 0.4 0.5" the bottom right.
    --app (name or bundle id) and --title match by case-insensitive substring. Without them the
    command applies to the focused window. --display moves the window to that display first.

    After moving windows, Paneful reads their frames back and reports where they really are.
    A line marked "differs" means the app refused the requested size (usually a minimum size).
    Add --json to any command for machine-readable output.

    Exit status: 0 done and verified, 3 done but not verified (a window differs or was skipped;
    the report still goes to stdout), 1 error, 2 Paneful is not running.

    apply reads a list of windows as JSON, from a file or from stdin with "-":
      [{"app": "Safari", "x": 0, "y": 0, "w": 0.6, "h": 1},
       {"app": "Notes", "title": "todo", "x": 0.6, "y": 0, "w": 0.4, "h": 1, "display": 2}]
    Each entry takes the first window that matches and hasn't been used yet.

    save and restore use \(defaultLayoutURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) unless you name a file.
    Run `paneful save` before rearranging, and `paneful restore` undoes it.
    """

    // MARK: Client (the `paneful` command)

    static func run(_ args: [String]) -> Int32 {
        guard let cmd = args.first else { print(usage); return 0 }
        if ["help", "--help", "-h"].contains(cmd) { print(usage); return 0 }
        if cmd == "actions" {
            Action.allCases.forEach { print("\($0.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \($0.title)") }
            return 0
        }
        let json = args.contains("--json")
        let positional = args.dropFirst().filter { $0 != "--json" }

        if cmd == "save" {
            let url = positional.first.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? defaultLayoutURL
            let (status, out) = send(["list", "--json"])
            guard status == 0 else { return finish(status, out) }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(out.utf8).write(to: url, options: .atomic)
            } catch { return finish(1, "error: could not write \(url.path): \(error.localizedDescription)") }
            let n = (try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [Any])?.count ?? 0
            return finish(0, json ? #"{"saved":\#(n),"file":"\#(url.path)"}"# : "saved \(n) windows to \(url.path)")
        }
        if cmd == "mcp" { return MCP.serve() }
        if cmd == "apply" {
            guard let src = positional.first else { return finish(1, "error: usage: paneful apply <file|->") }
            let data = src == "-" ? FileHandle.standardInput.readDataToEndOfFile()
                : FileManager.default.contents(atPath: (src as NSString).expandingTildeInPath)
            guard let d = data, let text = String(data: d, encoding: .utf8) else { return finish(1, "error: can't read \(src)") }
            let (status, out) = send(["apply", text] + (json ? ["--json"] : []))
            return finish(status, out)
        }
        if cmd == "restore" {
            let url = positional.first.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? defaultLayoutURL
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return finish(1, "error: no saved layout at \(url.path). Run `paneful save` first.")
            }
            let (status, out) = send(["restore", text] + (json ? ["--json"] : []))
            return finish(status, out)
        }
        let (status, out) = send(args)
        return finish(status, out)
    }

    /// Send one request to the running app and wait for its reply
    static func send(_ args: [String]) -> (Int32, String) {
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
            return (2, "error: Paneful is not running. Open Paneful.app first.")
        }
        let reply = NSTemporaryDirectory() + "paneful-\(UUID().uuidString).reply"
        let request: [String: Any] = ["args": args, "reply": reply, "token": token]
        guard let data = try? JSONSerialization.data(withJSONObject: request), let body = String(data: data, encoding: .utf8) else { return (2, "error: bad request") }
        DistributedNotificationCenter.default().postNotificationName(channel, object: body, userInfo: nil, deliverImmediately: true)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let data = FileManager.default.contents(atPath: reply),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = obj["status"] as? Int, let out = obj["out"] as? String {
                try? FileManager.default.removeItem(atPath: reply)
                return (Int32(status), out)
            }
            usleep(15_000)
        }
        return (2, "error: Paneful is not running. Open Paneful.app first.")
    }

    private static func finish(_ status: Int32, _ out: String) -> Int32 {
        let text = out.hasSuffix("\n") ? out : out + "\n"
        FileHandle(forWritingAtPath: status == 0 || status == 3 ? "/dev/stdout" : "/dev/stderr")?.write(Data(text.utf8))
        return status
    }

    // MARK: Server (inside the running app)

    private static var token = ""

    static func startServer() {
        token = newToken()
        DistributedNotificationCenter.default().addObserver(forName: channel, object: nil, queue: .main) { note in
            guard let body = note.object as? String,
                  let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let args = obj["args"] as? [String], !args.isEmpty,
                  let reply = obj["reply"] as? String, isSafeReplyPath(reply, tmp: NSTemporaryDirectory()),
                  let t = obj["token"] as? String, !token.isEmpty, t == token else { return }
            let (status, out) = handle(args)
            let answer: [String: Any] = ["status": status, "out": out]
            if let data = try? JSONSerialization.data(withJSONObject: answer) { try? data.write(to: URL(fileURLWithPath: reply), options: .atomic) }
        }
    }

    /// A fresh random token per launch, readable only by this user
    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        let dir = tokenURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.removeItem(at: tokenURL)
            guard fm.createFile(atPath: tokenURL.path, contents: Data(t.utf8), attributes: [.posixPermissions: 0o600]) else { return "" }
        } catch { logLine("cli token: \(error.localizedDescription)"); return "" }
        return t
    }

    /// Replies may only go to a file named like the client's, directly inside our temporary directory
    static func isSafeReplyPath(_ path: String, tmp: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        guard url.deletingLastPathComponent().path == URL(fileURLWithPath: tmp).standardizedFileURL.path,
              name.hasPrefix("paneful-"), name.hasSuffix(".reply") else { return false }
        return UUID(uuidString: String(name.dropFirst(8).dropLast(6))) != nil
    }

    private static func handle(_ args: [String]) -> (Int32, String) {
        var rest = Array(args.dropFirst())
        let json = rest.contains("--json")
        rest.removeAll { $0 == "--json" }
        func fail(_ msg: String) -> (Int32, String) { (1, json ? encode(["error": msg]) : "error: " + msg) }
        guard AX.trusted else { return fail("Paneful does not have the Accessibility permission. Open the Paneful menu in the menu bar to fix it.") }
        func option(_ name: String) -> String? {
            guard let i = rest.firstIndex(of: name), i + 1 < rest.count else { return nil }
            let v = rest[i + 1]
            rest.removeSubrange(i...i + 1)
            return v
        }
        let app = option("--app"), title = option("--title"), displayArg = option("--display")
        var display: NSScreen?
        if let d = displayArg {
            let screens = orderedScreens()
            guard let n = Int(d), screens.indices.contains(n - 1) else { return fail("there is no display \(d). Run `paneful displays`.") }
            display = screens[n - 1]
        }

        switch args[0] {
        case "list":
            let wins = AX.windowsFrontToBack()
            let infos = wins.enumerated().map { i, w in info(w.window, frame: w.frame, index: i + 1) }
            if json { return (0, encode(infos)) }
            return (0, infos.isEmpty ? "no windows" : infos.map(line).joined(separator: "\n"))

        case "displays":
            let list = orderedScreens().enumerated().map { i, s -> [String: Any] in
                ["display": i + 1, "name": s.localizedName, "main": s == NSScreen.main,
                 "frame": rect(flip(s.frame)), "visible": rect(flip(s.visibleFrame))]
            }
            if json { return (0, encode(list)) }
            return (0, list.map { d in
                let f = d["frame"] as! [String: Int]
                return "\(d["display"]!)  \(d["name"]!)  \(f["w"]!)×\(f["h"]!) at x=\(f["x"]!) y=\(f["y"]!)\((d["main"] as! Bool) ? "  (main)" : "")"
            }.joined(separator: "\n"))

        case "tile":
            let placed = WindowManager.shared.tileAll()
            return report(placed, verb: "tiled", json: json)

        case "run":
            guard let name = rest.first, let action = Action(rawValue: name) else {
                return fail("unknown action. Run `paneful actions` to see the names.")
            }
            if action == .tileAll { return report(WindowManager.shared.tileAll(), verb: "tiled", json: json) }
            if action == .focusNextDisplay {
                guard let n = WindowManager.shared.focusNextDisplay() else { return fail("there is only one display") }
                return (0, json ? encode(["display": n]) : "focused display \(n)")
            }
            guard let w = target(app: app, title: title) else { return fail(notFound(app, title)) }
            return moveAndReport(w, json: json) { WindowManager.shared.perform(action, on: w, screen: display) }

        case "place":
            let n = rest.prefix(4).compactMap { Double($0) }
            guard n.count == 4, n[2] > 0, n[3] > 0, n[0] >= 0, n[1] >= 0, n[0] + n[2] <= 1.001, n[1] + n[3] <= 1.001 else {
                return fail("place needs four numbers within 0–1: x y w h")
            }
            guard let w = target(app: app, title: title) else { return fail(notFound(app, title)) }
            let layout = CustomLayout(name: "cli", key: nil, x: n[0], y: n[1], w: n[2], h: n[3])
            return moveAndReport(w, json: json) { WindowManager.shared.perform(layout, on: w, screen: display) }

        case "fullscreen":
            guard let mode = rest.first, ["on", "off"].contains(mode), let name = app else {
                return fail("usage: paneful fullscreen <on|off> --app NAME")
            }
            let n = AX.setFullScreen(mode == "on", app: name)
            return (0, json ? encode(["changed": n]) : "changed \(n) window(s)")

        case "apply":
            let parsed = parseLayout(rest.first ?? "")
            if let e = parsed.error { return fail(e) }
            return apply(parsed.entries, json: json)

        case "restore":
            guard let text = rest.first, let saved = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
                return fail("the saved layout is not a list of windows. Save it again with `paneful save`.")
            }
            return restore(saved, json: json)

        default:
            return fail("unknown command \"\(args[0])\". Run `paneful help`.")
        }
    }

    // MARK: Moving and reporting

    /// Run a move, wait for the window to settle, and report where it really ended up
    private static func moveAndReport(_ w: AXUIElement, json: Bool, _ move: () -> Void) -> (Int32, String) {
        let wm = WindowManager.shared
        wm.lastTarget = nil
        move()
        guard let t = wm.lastTarget else {
            return (1, json ? encode(["error": "the window did not move"]) : "error: the window did not move")
        }
        return report([(w, t)], verb: "moved", json: json)
    }

    /// Read every moved window back and say whether the result is verified: each window where it was
    /// asked to be, and nothing skipped. Exit status 0 when verified, 3 when not.
    private static func report(_ placed: [(window: AXUIElement, target: CGRect)], skipped: [[String: Any]] = [],
                               verb: String, json: Bool) -> (Int32, String) {
        let actual = settle(placed)
        let results = zip(placed, actual).enumerated().map { i, pair -> [String: Any] in
            var d = info(pair.0.window, frame: pair.1, index: i + 1)
            d["target"] = rect(pair.0.target)
            d["matchesTarget"] = nearlyEqual(pair.1, pair.0.target, tol: 3)
            return d
        }
        let differ = results.filter { $0["matchesTarget"] as? Bool == false }.count
        let verified = differ == 0 && skipped.isEmpty
        let status: Int32 = verified ? 0 : 3
        if json { return (status, encode([verb: results.count, "windows": results, "skipped": skipped, "verified": verified])) }
        var out = "\(verb) \(results.count) window\(results.count == 1 ? "" : "s")"
        if differ > 0 { out += ", \(differ) differ from the requested frame (the app enforces a size)" }
        if !skipped.isEmpty { out += ", \(skipped.count) skipped" }
        out += verified ? " (verified)" : " (not verified)"
        let skippedLines = skipped.map { "skipped  app=\"\($0["app"] ?? "")\"  title=\"\($0["title"] ?? "")\"  (\($0["reason"] ?? ""))" }
        return (status, ([out] + results.map(line) + skippedLines).joined(separator: "\n"))
    }

    /// Read frames back, giving slow apps up to about half a second to finish resizing
    private static func settle(_ placed: [(window: AXUIElement, target: CGRect)]) -> [CGRect] {
        var frames: [CGRect] = []
        for _ in 0..<12 {
            frames = placed.map { AX.frame(of: $0.window) ?? .null }
            if zip(frames, placed).allSatisfy({ nearlyEqual($0, $1.target, tol: 3) }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        // The window server's on-screen list (which `list` and the next command start from) lags
        // the Accessibility frame for a moment after a move. Wait for it too, so a call made right
        // after this one still finds every window that just moved.
        for _ in 0..<12 {
            let listed = AX.windowsFrontToBack().map(\.window)
            if placed.allSatisfy({ p in listed.contains { CFEqual($0, p.window) } }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return frames
    }

    private static func restore(_ saved: [[String: Any]], json: Bool) -> (Int32, String) {
        let current = AX.windowsFrontToBack()
        let currentKeys = current.map { w -> (bundle: String, title: String) in
            let d = AX.describe(w.window); return (d.bundleID, d.title)
        }
        let savedKeys = saved.map { (($0["bundleID"] as? String) ?? "", ($0["title"] as? String) ?? "") }
        let matches = matchWindows(saved: savedKeys, current: currentKeys)
        let screens = NSScreen.screens.map { flip($0.frame) }

        var placed: [(window: AXUIElement, target: CGRect)] = []
        var skipped: [[String: Any]] = []
        for (entry, m) in zip(saved, matches) {
            let label: [String: Any] = ["app": entry["app"] ?? "", "title": entry["title"] ?? ""]
            guard let f = entry["frame"] as? [String: Any],
                  let x = f["x"] as? Double, let y = f["y"] as? Double, let w = f["w"] as? Double, let h = f["h"] as? Double else {
                skipped.append(label.merging(["reason": "no frame saved"]) { a, _ in a }); continue
            }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            guard let i = m else { skipped.append(label.merging(["reason": "window not found"]) { a, _ in a }); continue }
            guard screens.contains(where: { $0.intersection(frame).area > frame.area / 2 }) else {
                skipped.append(label.merging(["reason": "its display is not connected"]) { a, _ in a }); continue
            }
            WindowManager.shared.move(current[i].window, to: frame)
            placed.append((current[i].window, frame))
        }
        return report(placed, skipped: skipped, verb: "restored", json: json)
    }

    /// One window in a layout for `paneful apply`: which window, and where as screen fractions
    struct LayoutEntry: Equatable {
        var app: String?
        var title: String?
        var unit: CGRect
        var display: Int?
    }

    /// Read a layout: a JSON list of entries, or {"windows": [...]}. Returns the first problem found.
    static func parseLayout(_ text: String) -> (entries: [LayoutEntry], error: String?) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return ([], "the layout is not valid JSON") }
        guard let list = (obj as? [[String: Any]]) ?? ((obj as? [String: Any])?["windows"] as? [[String: Any]]), !list.isEmpty else {
            return ([], "the layout must be a non-empty list of windows")
        }
        var out: [LayoutEntry] = []
        for (i, e) in list.enumerated() {
            let n = i + 1
            let app = e["app"] as? String, title = e["title"] as? String
            guard app != nil || title != nil else { return ([], "window \(n): give \"app\" or \"title\"") }
            let v = ["x", "y", "w", "h"].map { (e[$0] as? NSNumber)?.doubleValue }
            guard let x = v[0], let y = v[1], let w = v[2], let h = v[3],
                  w > 0, h > 0, x >= 0, y >= 0, x + w <= 1.001, y + h <= 1.001 else {
                return ([], "window \(n): x, y, w, h must be numbers within 0–1")
            }
            var display: Int?
            if let d = e["display"] {
                guard let dn = (d as? NSNumber)?.intValue, dn >= 1 else { return ([], "window \(n): display must be 1 or more") }
                display = dn
            }
            out.append(LayoutEntry(app: app, title: title, unit: CGRect(x: x, y: y, width: w, height: h), display: display))
        }
        return (out, nil)
    }

    private static func apply(_ entries: [LayoutEntry], json: Bool) -> (Int32, String) {
        let current = AX.windowsFrontToBack()
        let screens = orderedScreens()
        var used = Set<Int>()
        var placed: [(window: AXUIElement, target: CGRect)] = []
        var skipped: [[String: Any]] = []
        for e in entries {
            let label: [String: Any] = ["app": e.app ?? "", "title": e.title ?? ""]
            guard let i = current.indices.first(where: { i in
                let (name, t, bundle) = AX.describe(current[i].window)
                return !used.contains(i)
                    && (e.app.map { name.localizedCaseInsensitiveContains($0) || bundle.localizedCaseInsensitiveContains($0) } ?? true)
                    && (e.title.map { t.localizedCaseInsensitiveContains($0) } ?? true)
            }) else { skipped.append(label.merging(["reason": "window not found"]) { a, _ in a }); continue }
            var screen: NSScreen?
            if let d = e.display {
                guard screens.indices.contains(d - 1) else { skipped.append(label.merging(["reason": "there is no display \(d)"]) { a, _ in a }); continue }
                screen = screens[d - 1]
            }
            used.insert(i)
            let wm = WindowManager.shared
            wm.lastTarget = nil
            wm.perform(CustomLayout(name: "apply", key: nil, x: e.unit.minX, y: e.unit.minY, w: e.unit.width, h: e.unit.height),
                       on: current[i].window, screen: screen)
            if let t = wm.lastTarget { placed.append((current[i].window, t)) }
            else { skipped.append(label.merging(["reason": "the window could not be moved"]) { a, _ in a }) }
        }
        return report(placed, skipped: skipped, verb: "applied", json: json)
    }

    /// Pair saved windows with current ones: same app and title first, then same app in order
    static func matchWindows(saved: [(bundle: String, title: String)], current: [(bundle: String, title: String)]) -> [Int?] {
        var used = Set<Int>()
        var result = [Int?](repeating: nil, count: saved.count)
        for (i, s) in saved.enumerated() {
            if let j = current.indices.first(where: { !used.contains($0) && current[$0] == s }) { result[i] = j; used.insert(j) }
        }
        for (i, s) in saved.enumerated() where result[i] == nil && !s.bundle.isEmpty {
            if let j = current.indices.first(where: { !used.contains($0) && current[$0].bundle == s.bundle }) { result[i] = j; used.insert(j) }
        }
        return result
    }

    // MARK: Describing windows and displays

    /// Displays numbered the way `--display` counts them: left to right, then top to bottom
    static func orderedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        return displayOrder(screens.map { flip($0.frame) }).map { screens[$0] }
    }

    private static func info(_ w: AXUIElement, frame: CGRect, index: Int) -> [String: Any] {
        let (name, title, bundle) = AX.describe(w)
        var d: [String: Any] = ["index": index, "app": name, "bundleID": bundle, "title": title, "frame": rect(frame)]
        let screens = orderedScreens()
        if let scr = WindowManager.shared.screen(for: frame), let n = screens.firstIndex(of: scr) {
            let v = flip(scr.visibleFrame)
            func r(_ x: CGFloat) -> Double { (Double(x) * 100).rounded() / 100 }
            d["display"] = n + 1
            d["unit"] = ["x": r((frame.minX - v.minX) / v.width), "y": r((frame.minY - v.minY) / v.height),
                         "w": r(frame.width / v.width), "h": r(frame.height / v.height)]
        }
        return d
    }

    private static func line(_ d: [String: Any]) -> String {
        var s = "\(d["index"]!)  app=\"\(d["app"]!)\"  title=\"\(d["title"]!)\""
        if let n = d["display"] { s += "  display=\(n)" }
        if let u = d["unit"] as? [String: Double] {
            s += "  " + ["x", "y", "w", "h"].map { "\($0)=\(String(format: "%.2f", u[$0] ?? 0))" }.joined(separator: " ")
        }
        if d["matchesTarget"] as? Bool == false, let t = d["target"] as? [String: Int], let f = d["frame"] as? [String: Int] {
            s += "  differs: asked \(t["w"]!)×\(t["h"]!), got \(f["w"]!)×\(f["h"]!)"
        }
        return s
    }

    private static func rect(_ r: CGRect) -> [String: Int] {
        r.isNull ? [:] : ["x": Int(r.minX.rounded()), "y": Int(r.minY.rounded()), "w": Int(r.width.rounded()), "h": Int(r.height.rounded())]
    }

    private static func encode(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func target(app: String?, title: String?) -> AXUIElement? {
        if app == nil && title == nil { return AX.focusedWindow() }
        return AX.windowsFrontToBack().first { w in
            let (name, t, bundle) = AX.describe(w.window)
            return (app.map { name.localizedCaseInsensitiveContains($0) || bundle.localizedCaseInsensitiveContains($0) } ?? true)
                && (title.map { t.localizedCaseInsensitiveContains($0) } ?? true)
        }?.window
    }

    private static func notFound(_ app: String?, _ title: String?) -> String {
        if app == nil && title == nil { return "there is no focused window" }
        return "no window matches" + (app.map { " app \"\($0)\"" } ?? "") + (title.map { " title \"\($0)\"" } ?? "") + ". Run `paneful list`."
    }
}
