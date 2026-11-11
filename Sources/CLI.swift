// Command line interface, so scripts and AI agents can drive Paneful.
//
//   paneful list                               every window, front to back
//   paneful tile                               tile all windows
//   paneful run <action> [--app A] [--title T] run a built-in action
//   paneful place <x> <y> <w> <h> [--app A] [--title T]
//   paneful actions                            list action names
//
// The command line process has no Accessibility permission of its own. It
// sends the request to the running app, which does the work and writes the
// reply to a temporary file.

import AppKit
import ApplicationServices

enum CLI {
    static let commands: Set<String> = ["list", "tile", "run", "place", "fullscreen", "actions", "help", "--help", "-h"]
    static let channel = Notification.Name("io.github.paneful.command")

    static let usage = """
    paneful: drive the Paneful window manager from scripts and agents.

      paneful list                                 list windows, front to back
      paneful tile                                 tile every window into a grid
      paneful run <action> [--app A] [--title T]   run a built-in action
      paneful place <x> <y> <w> <h> [--app A] [--title T]
                                                   put a window at a position
      paneful fullscreen <on|off> --app A          enter or leave native fullscreen
      paneful actions                              list the action names

    Positions are fractions of the screen from 0 to 1, origin at the top left:
    "place 0 0 0.6 1" is the left 60%, "place 0.6 0.5 0.4 0.5" the bottom right.
    --app (name or bundle id) and --title match by case-insensitive substring. Without them the
    command applies to the focused window. Chain commands with && to build a layout.
    """

    // MARK: Client (the `paneful` command)

    static func run(_ args: [String]) -> Int32 {
        guard let cmd = args.first else { print(usage); return 0 }
        if ["help", "--help", "-h"].contains(cmd) { print(usage); return 0 }
        if cmd == "actions" {
            Action.allCases.forEach { print("\($0.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \($0.title)") }
            return 0
        }
        let reply = NSTemporaryDirectory() + "paneful-\(UUID().uuidString).reply"
        let request: [String: Any] = ["args": args, "reply": reply]
        guard let data = try? JSONSerialization.data(withJSONObject: request), let json = String(data: data, encoding: .utf8) else { return 2 }
        DistributedNotificationCenter.default().postNotificationName(channel, object: json, userInfo: nil, deliverImmediately: true)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: reply, encoding: .utf8), text.hasSuffix("\n") {
                try? FileManager.default.removeItem(atPath: reply)
                let failed = text.hasPrefix("error:")
                FileHandle(forWritingAtPath: failed ? "/dev/stderr" : "/dev/stdout")?.write(Data(text.utf8))
                return failed ? 1 : 0
            }
            usleep(15_000)
        }
        FileHandle.standardError.write(Data("error: Paneful is not running. Open Paneful.app first.\n".utf8))
        return 2
    }

    // MARK: Server (inside the running app)

    static func startServer() {
        DistributedNotificationCenter.default().addObserver(forName: channel, object: nil, queue: .main) { note in
            guard let json = note.object as? String,
                  let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let args = obj["args"] as? [String], let reply = obj["reply"] as? String,
                  reply.hasPrefix(NSTemporaryDirectory()), reply.hasSuffix(".reply") else { return }
            var out = handle(args)
            if !out.hasSuffix("\n") { out += "\n" }
            try? out.write(toFile: reply, atomically: true, encoding: .utf8)
        }
    }

    private static func handle(_ args: [String]) -> String {
        guard AX.trusted else { return "error: Paneful does not have the Accessibility permission yet." }
        var rest = Array(args.dropFirst())
        func option(_ name: String) -> String? {
            guard let i = rest.firstIndex(of: name), i + 1 < rest.count else { return nil }
            let v = rest[i + 1]
            rest.removeSubrange(i...i + 1)
            return v
        }
        let app = option("--app"), title = option("--title")

        switch args[0] {
        case "list":
            let wins = AX.windowsFrontToBack()
            if wins.isEmpty { return "no windows" }
            return wins.enumerated().map { i, w in
                let (name, title, _) = AX.describe(w.window)
                let v = WindowManager.shared.screen(for: w.frame).map { flip($0.visibleFrame) } ?? .zero
                func f(_ x: CGFloat) -> String { String(format: "%.2f", x) }
                let pos = v.width > 0 ? "x=\(f((w.frame.minX - v.minX) / v.width)) y=\(f((w.frame.minY - v.minY) / v.height)) w=\(f(w.frame.width / v.width)) h=\(f(w.frame.height / v.height))" : ""
                return "\(i + 1)  app=\"\(name)\"  title=\"\(title)\"  \(pos)"
            }.joined(separator: "\n")

        case "tile":
            WindowManager.shared.tileAll()
            return "tiled \(min(AX.windowsFrontToBack().count, ConfigStore.shared.config.tile.max)) windows"

        case "run":
            guard let name = rest.first, let action = Action(rawValue: name) else {
                return "error: unknown action. Run `paneful actions` to see the names."
            }
            if action == .tileAll { WindowManager.shared.tileAll(); return "ok" }
            guard let w = target(app: app, title: title) else { return notFound(app, title) }
            WindowManager.shared.perform(action, on: w)
            return "ok"

        case "place":
            let n = rest.prefix(4).compactMap { Double($0) }
            guard n.count == 4, n[2] > 0, n[3] > 0, n[0] >= 0, n[1] >= 0, n[0] + n[2] <= 1.001, n[1] + n[3] <= 1.001 else {
                return "error: place needs four numbers within 0–1: x y w h"
            }
            guard let w = target(app: app, title: title) else { return notFound(app, title) }
            WindowManager.shared.perform(CustomLayout(name: "cli", key: nil, x: n[0], y: n[1], w: n[2], h: n[3]), on: w)
            return "ok"

        case "fullscreen":
            guard let mode = rest.first, ["on", "off"].contains(mode), let name = app else {
                return "error: usage: paneful fullscreen <on|off> --app NAME"
            }
            return "changed \(AX.setFullScreen(mode == "on", app: name)) window(s)"

        default:
            return "error: unknown command \"\(args[0])\". Run `paneful help`."
        }
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
        if app == nil && title == nil { return "error: there is no focused window" }
        return "error: no window matches" + (app.map { " app \"\($0)\"" } ?? "") + (title.map { " title \"\($0)\"" } ?? "") + ". Run `paneful list`."
    }
}
