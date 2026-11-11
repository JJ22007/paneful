// 入口。
//   Fenping                  正常启动(菜单栏 App)
//   Fenping --selftest       跑几何、快捷键、配置的自测
//   Fenping --check <文件>   检查一份配置文件有没有问题
//   Fenping --snapshot <目录> 把欢迎界面的每一步渲染成 PNG

import AppKit
import SwiftUI

/// 项目主页。Fork 之后改成你自己的地址。
let repoURL = "https://github.com/JJ22007/fenping"

func selfTest() -> Int32 {
    var fails = 0
    func expect(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { fails += 1 }
        print("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }
    func check(_ name: String, _ got: CGRect?, _ want: CGRect) {
        expect(name, got.map { nearlyEqual($0, want, tol: 1) } ?? false, got.map { "\($0)" } ?? "nil")
    }

    let v = CGRect(x: 0, y: 33, width: 1512, height: 900)
    let c = CGRect(x: 100, y: 100, width: 800, height: 600)
    check("左半屏", targetRect(.leftHalf, visible: v, current: c), CGRect(x: 0, y: 33, width: 756, height: 900))
    check("左半屏 连按→2/3", targetRect(.leftHalf, visible: v, current: c, cycle: 1), CGRect(x: 0, y: 33, width: 1008, height: 900))
    check("左半屏 连按→1/3", targetRect(.leftHalf, visible: v, current: c, cycle: 2), CGRect(x: 0, y: 33, width: 504, height: 900))
    check("右半屏 连按→2/3", targetRect(.rightHalf, visible: v, current: c, cycle: 1), CGRect(x: 504, y: 33, width: 1008, height: 900))
    check("右下 1/4", targetRect(.bottomRight, visible: v, current: c), CGRect(x: 756, y: 483, width: 756, height: 450))
    check("中 1/3", targetRect(.centerThird, visible: v, current: c), CGRect(x: 504, y: 33, width: 504, height: 900))
    check("最大化", targetRect(.maximize, visible: v, current: c), v)
    check("居中", targetRect(.center, visible: v, current: c), CGRect(x: 356, y: 183, width: 800, height: 600))
    check("左半屏 间距12", targetRect(.leftHalf, visible: v, current: c, gap: 12), CGRect(x: 12, y: 45, width: 738, height: 876))
    check("右半屏 间距12", targetRect(.rightHalf, visible: v, current: c, gap: 12), CGRect(x: 762, y: 45, width: 738, height: 876))
    check("自定义位置", screenRect(unit: CGRect(x: 0.62, y: 0, width: 0.38, height: 1), visible: v), CGRect(x: 937, y: 33, width: 575, height: 900))
    check("跨屏映射", remap(CGRect(x: 0, y: 33, width: 756, height: 900), from: v, to: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
          CGRect(x: 1512, y: 0, width: 1280, height: 1440))

    expect("排列规则 2/3/4/5/6", [2, 3, 4, 5, 6].map(defaultTileRows) == [[2], [3], [2, 2], [3, 2], [3, 3]])
    expect("排列规则 7/8/10", [7, 8, 10].map(defaultTileRows) == [[3, 2, 2], [3, 3, 2], [4, 3, 3]])
    check("排列4 右下", tileLayout(rows: [2, 2], visible: v)[3], CGRect(x: 756, y: 483, width: 756, height: 450))
    check("排列5 上排第3个", tileLayout(rows: [3, 2], visible: v)[2], CGRect(x: 1008, y: 33, width: 504, height: 450))

    let k = KeyCombo.parse("ctrl+alt+left")
    expect("快捷键 ctrl+alt+left", k?.code == 123 && k?.pretty == "⌃⌥←", k?.pretty ?? "nil")
    expect("快捷键 Cmd+Shift+F5", KeyCombo.parse("Cmd+Shift+F5")?.pretty == "⇧⌘F5")
    expect("快捷键 无修饰键被拒绝", KeyCombo.parse("a") == nil)
    expect("快捷键 乱写被拒绝", KeyCombo.parse("ctrl+banana") == nil && KeyCombo.parse("hyper+a") == nil)
    expect("默认快捷键全部可解析且不重复", Set(Action.allCases.compactMap { KeyCombo.parse($0.defaultShortcut)?.pretty }).count == Action.allCases.count)

    func decode(_ json: String) -> Config? { try? JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
    let empty = decode("{}")
    expect("配置 空对象=默认", empty == Config())
    let partial = decode(#"{"gap": 8, "shortcuts": {"maximize": "ctrl+alt+m", "center": ""}, "tile": {"rows": {"5": [2, 3]}}}"#)
    expect("配置 只写要改的", partial?.gap == 8 && partial?.shortcuts["maximize"] == "ctrl+alt+m"
        && partial?.shortcuts["leftHalf"] == "ctrl+alt+left" && partial?.tile.rows(for: 5) == [2, 3] && partial?.tile.rows(for: 4) == [2, 2])
    expect("配置 示例片段可解析", decode(exampleSnippet)?.custom.count == 2 && decode(exampleSnippet)?.warnings().isEmpty == true)
    let bad = decode(#"{"shortcuts": {"nope": "ctrl+a", "center": "what"}, "custom": [{"name": "x", "x": 0.8, "y": 0, "w": 0.5, "h": 1}], "tile": {"rows": {"5": [2, 2]}}}"#)
    expect("配置 能查出 4 处问题", bad?.warnings().count == 4, "\(bad?.warnings() ?? [])")
    expect("配置 JSON 写错会报错", decode("{ \"gap\": }") == nil)

    let f = CGRect(x: 0, y: 0, width: 1512, height: 982)
    expect("拖边 左/右/顶", DragSnapper.zone(at: CGPoint(x: 0, y: 500), in: f) == .leftHalf
        && DragSnapper.zone(at: CGPoint(x: 1511, y: 500), in: f) == .rightHalf
        && DragSnapper.zone(at: CGPoint(x: 700, y: 981), in: f) == .maximize)
    expect("拖边 角落/中间", DragSnapper.zone(at: CGPoint(x: 0, y: 981), in: f) == .topLeft
        && DragSnapper.zone(at: CGPoint(x: 1511, y: 20), in: f) == .bottomRight
        && DragSnapper.zone(at: CGPoint(x: 700, y: 500), in: f) == nil)

    print(fails == 0 ? "全部通过" : "\(fails) 项失败")
    return fails == 0 ? 0 : 1
}

func checkConfig(_ path: String) -> Int32 {
    do {
        let cfg = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let w = cfg.warnings()
        w.forEach { print("⚠️  \($0)") }
        print(w.isEmpty ? "\(path): 没有问题" : "\(path): \(w.count) 处问题")
        return w.isEmpty ? 0 : 1
    } catch let e as DecodingError {
        print("\(path): \(ConfigStore.describe(e))"); return 1
    } catch {
        print("\(path): \(error.localizedDescription)"); return 1
    }
}

/// 把欢迎界面每一步画成 PNG(给 README 用,也方便改完界面后检查)
func snapshot(to dir: String) -> Int32 {
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for step in 0..<WelcomeModel.stepCount {
        let model = WelcomeModel()
        model.step = step
        let host = NSHostingView(rootView: WelcomeView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        let path = "\(dir)/welcome-\(step + 1).png"
        do { try png.write(to: URL(fileURLWithPath: path)); print(path) } catch { print(error); return 1 }
    }
    return 0
}

let args = CommandLine.arguments
if args.contains("--selftest") { exit(selfTest()) }
if let i = args.firstIndex(of: "--check"), args.count > i + 1 { exit(checkConfig(args[i + 1])) }
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 { exit(snapshot(to: args[i + 1])) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
