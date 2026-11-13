// The config file: ~/.config/paneful/config.json
// It is the single source of truth. Menu toggles write to it too, and manual
// edits are picked up within a second or two. No restart needed.

import Foundation

/// A user-defined position. x / y / w / h are fractions of the screen (0...1), origin at the top left.
struct CustomLayout: Codable, Equatable {
    var name: String
    var key: String?
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var unit: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// Rules for "tile all windows"
struct TileConfig: Codable, Equatable {
    /// Tile at most this many windows; the rest are left alone
    var max: Int = 6
    /// Window count → windows per row. "5": [3, 2] means three on top and two below.
    /// Counts that are not listed use the default rule.
    var rows: [String: [Int]] = [:]
    /// Window count → a named layout: "columns", "grid" or "gridSidebar". "3": "grid" puts three windows
    /// in a 2×2 grid with one corner free. `rows` wins when both are set for the same count.
    var shapes: [String: String] = [:]

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        max = try c.decodeIfPresent(Int.self, forKey: .max) ?? 6
        rows = try c.decodeIfPresent([String: [Int]].self, forKey: .rows) ?? [:]
        shapes = try c.decodeIfPresent([String: String].self, forKey: .shapes) ?? [:]
    }

    /// The named layout the user chose for n windows, if any
    func shape(for n: Int) -> TileShapeName? { shapes[String(n)].flatMap(TileShapeName.init(rawValue:)) }

    func rows(for n: Int) -> [Int] { customRows(for: n) ?? defaultTileRows(n) }

    /// The rows the user set for n windows, if they set valid ones
    func customRows(for n: Int) -> [Int]? {
        if let r = rows[String(n)], r.reduce(0, +) == n, r.allSatisfy({ $0 > 0 }) { return r }
        return nil
    }
}

struct Config: Codable, Equatable {
    /// Gap between windows, in points
    var gap: Double = 0
    /// Snap windows dragged to a screen edge
    var dragSnap: Bool = false
    /// Off: pressing left/right half again cycles its width. On: it carries the window to the next display instead.
    var crossDisplays: Bool = false
    /// Action name → shortcut. An empty string "" removes the shortcut.
    var shortcuts: [String: String] = Config.defaultShortcuts
    /// User-defined positions
    var custom: [CustomLayout] = []
    var tile = TileConfig()

    static var defaultShortcuts: [String: String] {
        Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0.rawValue, $0.defaultShortcut) })
    }

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0
        dragSnap = try c.decodeIfPresent(Bool.self, forKey: .dragSnap) ?? false
        crossDisplays = try c.decodeIfPresent(Bool.self, forKey: .crossDisplays) ?? false
        // Users only write the entries they want to change; the rest keep their defaults
        let user = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? [:]
        shortcuts = Config.defaultShortcuts.merging(user) { _, new in new }
        custom = try c.decodeIfPresent([CustomLayout].self, forKey: .custom) ?? []
        tile = try c.decodeIfPresent(TileConfig.self, forKey: .tile) ?? TileConfig()
    }

    /// Non-fatal problems. The offending entry is ignored and everything else keeps working.
    func warnings() -> [String] {
        var out: [String] = []
        for (name, key) in shortcuts.sorted(by: { $0.key < $1.key }) {
            if Action(rawValue: name) == nil { out.append("shortcuts: there is no action called \"\(name)\"") }
            else if !key.isEmpty, KeyCombo.parse(key) == nil { out.append("Can't read shortcut \"\(key)\" (\(name))") }
        }
        for l in custom {
            if let k = l.key, !k.isEmpty, KeyCombo.parse(k) == nil { out.append("Can't read shortcut \"\(k)\" (\(l.name))") }
            if l.w <= 0 || l.h <= 0 || l.x < 0 || l.y < 0 || l.x + l.w > 1.001 || l.y + l.h > 1.001 {
                out.append("\"\(l.name)\" is off screen (x, y, w, h must stay within 0–1)")
            }
        }
        for (n, r) in tile.rows.sorted(by: { $0.key < $1.key }) {
            if Int(n) == nil || r.reduce(0, +) != Int(n) || r.contains(where: { $0 <= 0 }) {
                out.append("tile.rows \"\(n)\": the row sizes must add up to \(n)")
            }
        }
        for (n, name) in tile.shapes.sorted(by: { $0.key < $1.key }) where TileShapeName(rawValue: name) == nil || Int(n) == nil {
            out.append("tile.shapes \"\(n)\": \"\(name)\" is not one of \(TileShapeName.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        if tile.max < 1 { out.append("tile.max must be at least 1") }
        // Two entries on one shortcut: only the first one registered would ever run
        var owners: [String: [String]] = [:]
        for (name, key) in shortcuts where Action(rawValue: name) != nil { if let k = KeyCombo.parse(key) { owners[k.pretty, default: []].append(name) } }
        for l in custom { if let key = l.key, let k = KeyCombo.parse(key) { owners[k.pretty, default: []].append(l.name) } }
        for (combo, names) in owners.sorted(by: { $0.key < $1.key }) where names.count > 1 {
            out.append("\(combo) is assigned to more than one thing: \(names.sorted().joined(separator: ", "))")
        }
        return out
    }
}

final class ConfigStore {
    static let shared = ConfigStore()

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/paneful/config.json")

    private(set) var config = Config()
    /// Set when the JSON itself is broken (a missing comma, say). The last good config stays in use.
    private(set) var parseError: String?
    var onChange: (() -> Void)?

    private var lastModified: Date?
    private var timer: Timer?

    /// Load the config, writing a default one if the file does not exist
    func start() {
        if !FileManager.default.fileExists(atPath: ConfigStore.url.path) { save() }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkForEdits() }
    }

    private func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: ConfigStore.url.path))?[.modificationDate] as? Date
    }

    private func checkForEdits() {
        if modified() != lastModified { reload(); onChange?() }
    }

    func reload() {
        lastModified = modified()
        do {
            let data = try Data(contentsOf: ConfigStore.url)
            config = try JSONDecoder().decode(Config.self, from: data)
            parseError = nil
        } catch let e as DecodingError {
            parseError = ConfigStore.describe(e)
        } catch {
            parseError = error.localizedDescription
        }
    }

    /// Change a setting from the menu or the welcome window
    func update(_ change: (inout Config) -> Void) {
        change(&config)
        save()
        onChange?()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(config) else { return }
        try? FileManager.default.createDirectory(at: ConfigStore.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: ConfigStore.url, options: .atomic)
        lastModified = modified()
        parseError = nil
    }

    static func describe(_ e: DecodingError) -> String {
        func path(_ c: DecodingError.Context) -> String {
            let p = c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            return p.isEmpty ? "" : " at \(p)"
        }
        switch e {
        case .dataCorrupted(let c):
            let detail = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return "Invalid JSON\(path(c)): \(detail ?? c.debugDescription)"
        case .typeMismatch(_, let c): return "Wrong type\(path(c)): \(c.debugDescription)"
        case .keyNotFound(let k, let c): return "Missing field \"\(k.stringValue)\"\(path(c))"
        case .valueNotFound(_, let c): return "Missing value\(path(c))"
        @unknown default: return "Could not read the config"
        }
    }
}
