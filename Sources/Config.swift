// 配置文件:~/.config/fenping/config.json
// 这是唯一的设置来源。菜单里的开关也是改这个文件;手动编辑后保存即生效,不用重启。

import Foundation

/// 用户自定义的位置:x / y / w / h 都是 0~1 的屏幕比例,原点在左上角。
struct CustomLayout: Codable, Equatable {
    var name: String
    var key: String?
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var unit: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// 一键排列的规则
struct TileConfig: Codable, Equatable {
    /// 最多排几个窗口,更多的保持不动
    var max: Int = 6
    /// 窗口数 → 每行放几个。例如 "5": [3, 2] 表示 5 个窗口时上排 3 个、下排 2 个。没写的数量用默认规则。
    var rows: [String: [Int]] = [:]

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        max = try c.decodeIfPresent(Int.self, forKey: .max) ?? 6
        rows = try c.decodeIfPresent([String: [Int]].self, forKey: .rows) ?? [:]
    }

    func rows(for n: Int) -> [Int] {
        if let r = rows[String(n)], r.reduce(0, +) == n, r.allSatisfy({ $0 > 0 }) { return r }
        return defaultTileRows(n)
    }
}

struct Config: Codable, Equatable {
    /// 窗口间距(pt)
    var gap: Double = 0
    /// 拖到屏幕边缘吸附
    var dragSnap: Bool = false
    /// 动作名 → 快捷键。写成空字符串 "" 表示不要这个快捷键。
    var shortcuts: [String: String] = Config.defaultShortcuts
    /// 自定义位置
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
        // 用户只需要写想改的那几个,其余沿用默认
        let user = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? [:]
        shortcuts = Config.defaultShortcuts.merging(user) { _, new in new }
        custom = try c.decodeIfPresent([CustomLayout].self, forKey: .custom) ?? []
        tile = try c.decodeIfPresent(TileConfig.self, forKey: .tile) ?? TileConfig()
    }

    /// 检查出来的小问题。不致命:有问题的那一项会被忽略,其余照常生效。
    func warnings() -> [String] {
        var out: [String] = []
        for (name, key) in shortcuts.sorted(by: { $0.key < $1.key }) {
            if Action(rawValue: name) == nil { out.append("shortcuts 里没有 \"\(name)\" 这个动作") }
            else if !key.isEmpty, KeyCombo.parse(key) == nil { out.append("看不懂快捷键 \"\(key)\"(\(name))") }
        }
        for l in custom {
            if let k = l.key, !k.isEmpty, KeyCombo.parse(k) == nil { out.append("看不懂快捷键 \"\(k)\"(\(l.name))") }
            if l.w <= 0 || l.h <= 0 || l.x < 0 || l.y < 0 || l.x + l.w > 1.001 || l.y + l.h > 1.001 {
                out.append("\"\(l.name)\" 的位置超出了屏幕(x/y/w/h 应在 0~1 之间)")
            }
        }
        for (n, r) in tile.rows.sorted(by: { $0.key < $1.key }) {
            if Int(n) == nil || r.reduce(0, +) != Int(n) || r.contains(where: { $0 <= 0 }) {
                out.append("tile.rows 的 \"\(n)\": 每行数量加起来应该等于 \(n)")
            }
        }
        if tile.max < 1 { out.append("tile.max 至少是 1") }
        return out
    }
}

final class ConfigStore {
    static let shared = ConfigStore()

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/fenping/config.json")

    private(set) var config = Config()
    /// JSON 本身写错了(少个逗号之类)时的错误信息。此时继续使用上一份能用的配置。
    private(set) var parseError: String?
    var onChange: (() -> Void)?

    private var lastModified: Date?
    private var timer: Timer?

    /// 读取配置;文件不存在就写一份默认的
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

    /// 从菜单或欢迎界面修改设置
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
            return p.isEmpty ? "" : "(\(p))"
        }
        switch e {
        case .dataCorrupted(let c):
            let detail = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return "JSON 格式有误\(path(c)):\(detail ?? c.debugDescription)"
        case .typeMismatch(_, let c): return "类型不对\(path(c)):\(c.debugDescription)"
        case .keyNotFound(let k, let c): return "缺少字段 \"\(k.stringValue)\"\(path(c))"
        case .valueNotFound(_, let c): return "缺少值\(path(c))"
        @unknown default: return "配置读取失败"
        }
    }
}
