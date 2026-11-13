// `paneful mcp`: the same commands as MCP tools, for agents and for other tools such as Knobs.
//
// Model Context Protocol over stdio: one JSON-RPC 2.0 message per line in, one per line out.
// Each tool call is forwarded to the running app exactly like the `paneful` command does it,
// so the permission, the token check and the read-back all stay in one place (CLI.swift).
// A tool result is an error unless the read-back verified it.

import Foundation

enum MCP {
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static let tools: [[String: Any]] = [
        tool("list_windows", "List visible windows front to back: app, bundle id, title, display, position as screen fractions, and frame in points. Optionally only those of one app, with a title, or on one display.", filters),
        tool("list_displays", "List displays, numbered left to right as apply_layout's \"display\" counts them.", [:]),
        tool("apply_layout", """
            Place several windows at once. Positions are fractions of the screen from 0 to 1, origin top left. \
            Each entry takes the first matching window not used yet. Paneful reads every window back; \
            the result is an error unless each window ended up where it was asked and none was skipped. \
            Call save_layout first if you may want to undo.
            """, [
                "windows": ["type": "array", "items": ["type": "object", "properties": [
                    "app": ["type": "string", "description": "App name or bundle id, case-insensitive substring"],
                    "title": ["type": "string", "description": "Window title, case-insensitive substring"],
                    "x": ["type": "number"], "y": ["type": "number"], "w": ["type": "number"], "h": ["type": "number"],
                    "display": ["type": "integer", "description": "1-based, from list_displays"],
                ], "required": ["x", "y", "w", "h"]]],
            ], required: ["windows"]),
        tool("tile_all", "Tile the visible windows, or only those of one app, with a title, or on one display. Windows that refuse to shrink get the room they need. Then report each window's real frame.", filters),
        tool("save_layout", "Return where every window is now. Keep the returned layout and pass it to restore_layout to undo.", [:]),
        tool("restore_layout", "Put windows back where save_layout found them, then read them back. Windows that are gone or whose display is disconnected are reported as skipped.", [
            "layout": ["type": "array", "items": ["type": "object"], "description": "The layout returned by save_layout"],
        ], required: ["layout"]),
    ]

    /// Optional filters shared by list_windows and tile_all, the same as the command line's --app, --title, --display
    private static let filters: [String: Any] = [
        "app": ["type": "string", "description": "App name or bundle id, case-insensitive substring"],
        "title": ["type": "string", "description": "Window title, case-insensitive substring"],
        "display": ["type": "integer", "description": "1-based, from list_displays"],
    ]

    private static func tool(_ name: String, _ description: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": props, "required": required] as [String: Any]]
    }

    static func serve() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine() {
            if let out = handle(line, call: CLI.send) { print(out) }
        }
        return 0
    }

    /// Answer one JSON-RPC line. `call` runs a `paneful` command and returns (exit status, output);
    /// the self-test passes a fake one. Notifications get no answer.
    static func handle(_ line: String, call: ([String]) -> (Int32, String)) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = msg["id"], let method = msg["method"] as? String else { return nil }
        let params = msg["params"] as? [String: Any] ?? [:]
        func result(_ r: Any) -> String { encode(["jsonrpc": "2.0", "id": id, "result": r]) }
        func error(_ code: Int, _ m: String) -> String { encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": m]]) }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return result([
                "protocolVersion": supportedVersions.contains(asked) ? asked : supportedVersions[0],
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "paneful", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": "Paneful arranges windows on this Mac. Every move is read back from macOS; a result is an error unless it was verified. Call save_layout before changing anything so restore_layout can undo it.",
            ])
        case "ping":
            return result([:] as [String: Any])
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String else { return error(-32602, "missing tool name") }
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let command = commandFor(name, args) else { return error(-32602, "unknown tool or bad arguments: \(name)") }
            let (status, out) = call(command)
            // Lists come back as JSON arrays; tool results must be objects
            var structured: [String: Any] = ["exitStatus": Int(status)]
            if let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) {
                if let d = obj as? [String: Any] { structured.merge(d) { a, _ in a } }
                else { structured[name == "save_layout" ? "layout" : name == "list_displays" ? "displays" : "windows"] = obj }
            } else {
                structured["message"] = out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return result(["content": [["type": "text", "text": encode(structured)]],
                           "structuredContent": structured, "isError": status != 0])
        default:
            return error(-32601, "method not found: \(method)")
        }
    }

    /// The `paneful` command a tool call maps to, or nil if the arguments are unusable
    static func commandFor(_ name: String, _ args: [String: Any]) -> [String]? {
        func json(_ v: Any) -> String? {
            (try? JSONSerialization.data(withJSONObject: v)).map { String(decoding: $0, as: UTF8.self) }
        }
        switch name {
        case "save_layout": return ["list", "--json"]
        case "list_displays": return ["displays", "--json"]
        case "list_windows", "tile_all":
            var c = [name == "list_windows" ? "list" : "tile", "--json"]
            if let a = args["app"] as? String { c += ["--app", a] }
            if let t = args["title"] as? String { c += ["--title", t] }
            if let d = args["display"] { guard let n = (d as? NSNumber)?.intValue else { return nil }; c += ["--display", String(n)] }
            return c
        case "apply_layout":
            guard let w = args["windows"] as? [Any], let s = json(w) else { return nil }
            return ["apply", s, "--json"]
        case "restore_layout":
            guard let l = args["layout"] as? [Any], let s = json(l) else { return nil }
            return ["restore", s, "--json"]
        default: return nil
        }
    }

    private static func encode(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
