// Entry point.
//   Paneful                   run normally (menu bar app)
//   Paneful --selftest        test geometry, shortcuts and config handling
//   Paneful --check <file>    validate a config file
//   Paneful --snapshot <dir>  render each welcome step to a PNG
//   Paneful list | displays | tile | run | place | fullscreen | save | restore | actions   command line interface, see CLI.swift

import AppKit
import SwiftUI

/// Project home page. Change this to your own URL when you fork.
let repoURL = "https://github.com/JJ22007/paneful"

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
    check("left half", targetRect(.leftHalf, visible: v, current: c), CGRect(x: 0, y: 33, width: 756, height: 900))
    check("left half, 2nd press → 2/3", targetRect(.leftHalf, visible: v, current: c, cycle: 1), CGRect(x: 0, y: 33, width: 1008, height: 900))
    check("left half, 3rd press → 1/3", targetRect(.leftHalf, visible: v, current: c, cycle: 2), CGRect(x: 0, y: 33, width: 504, height: 900))
    check("right half, 2nd press → 2/3", targetRect(.rightHalf, visible: v, current: c, cycle: 1), CGRect(x: 504, y: 33, width: 1008, height: 900))
    check("bottom right", targetRect(.bottomRight, visible: v, current: c), CGRect(x: 756, y: 483, width: 756, height: 450))
    check("center third", targetRect(.centerThird, visible: v, current: c), CGRect(x: 504, y: 33, width: 504, height: 900))
    check("maximize", targetRect(.maximize, visible: v, current: c), v)
    check("center", targetRect(.center, visible: v, current: c), CGRect(x: 356, y: 183, width: 800, height: 600))
    check("left half, gap 12", targetRect(.leftHalf, visible: v, current: c, gap: 12), CGRect(x: 12, y: 45, width: 738, height: 876))
    check("right half, gap 12", targetRect(.rightHalf, visible: v, current: c, gap: 12), CGRect(x: 762, y: 45, width: 738, height: 876))
    check("custom position", screenRect(unit: CGRect(x: 0.62, y: 0, width: 0.38, height: 1), visible: v), CGRect(x: 937, y: 33, width: 575, height: 900))
    check("remap across displays", remap(CGRect(x: 0, y: 33, width: 756, height: 900), from: v, to: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
          CGRect(x: 1512, y: 0, width: 1280, height: 1440))

    let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 2560, height: 1440), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
    expect("neighbor display: left / right / wraps", neighborDisplay(of: 0, in: displays, left: true) == 2
        && neighborDisplay(of: 0, in: displays, left: false) == 1 && neighborDisplay(of: 1, in: displays, left: false) == 2
        && neighborDisplay(of: 1, in: displays, left: true) == 0)
    expect("neighbor display: stacked pair swaps, single display has none", neighborDisplay(of: 0, in: [displays[0], CGRect(x: -373, y: -1440, width: 2560, height: 1440)], left: false) == 1
        && neighborDisplay(of: 0, in: [displays[0]], left: true) == nil)

    let lh = CGRect(x: 0, y: 33, width: 756, height: 900), rh = CGRect(x: 756, y: 33, width: 756, height: 900)
    expect("walk: right half leaves the display going right, left half and maximized do not",
           onOuterHalf(rh, visible: v, right: true) && !onOuterHalf(lh, visible: v, right: true) && !onOuterHalf(v, visible: v, right: true)
           && onOuterHalf(lh, visible: v, right: false) && !onOuterHalf(c, visible: v, right: false))

    expect("display order: left to right, then top to bottom", displayOrder(displays) == [2, 0, 1]
        && displayOrder([CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 0, y: -100, width: 100, height: 100)]) == [1, 0])

    let tmp = "/var/folders/xy/T/"
    expect("cli: reply path accepted only as our own file in the temp folder",
           CLI.isSafeReplyPath(tmp + "paneful-\(UUID().uuidString).reply", tmp: tmp)
           && !CLI.isSafeReplyPath(tmp + "../../Users/me/.zshrc.reply", tmp: tmp)
           && !CLI.isSafeReplyPath(tmp + "paneful-x/../../evil-\(UUID().uuidString).reply", tmp: tmp)
           && !CLI.isSafeReplyPath(tmp + "paneful-not-a-uuid.reply", tmp: tmp)
           && !CLI.isSafeReplyPath("/tmp/paneful-\(UUID().uuidString).reply", tmp: tmp))
    let m = CLI.matchWindows(saved: [("a", "Notes"), ("a", "Old title"), ("b", "Gone"), ("c", "Mail")],
                             current: [("a", "Draft"), ("c", "Mail"), ("a", "Notes")])
    expect("restore: match by app and title, then by app, else missing", m == [2, 0, nil, 1], "\(m)")

    expect("tile rows for 2/3/4/5/6", [2, 3, 4, 5, 6].map(defaultTileRows) == [[2], [3], [2, 2], [3, 2], [3, 3]])
    expect("tile rows for 7/8/10", [7, 8, 10].map(defaultTileRows) == [[3, 2, 2], [3, 3, 2], [4, 3, 3]])
    check("tile 4, bottom right", tileLayout(rows: [2, 2], visible: v)[3], CGRect(x: 756, y: 483, width: 756, height: 450))
    check("tile 5, third on top", tileLayout(rows: [3, 2], visible: v)[2], CGRect(x: 1008, y: 33, width: 504, height: 450))

    let k = KeyCombo.parse("ctrl+alt+left")
    expect("shortcut ctrl+alt+left", k?.code == 123 && k?.pretty == "⌃⌥←", k?.pretty ?? "nil")
    expect("shortcut Cmd+Shift+F5", KeyCombo.parse("Cmd+Shift+F5")?.pretty == "⇧⌘F5")
    expect("shortcut without a modifier is rejected", KeyCombo.parse("a") == nil)
    expect("nonsense shortcuts are rejected", KeyCombo.parse("ctrl+banana") == nil && KeyCombo.parse("hyper+a") == nil)
    expect("default shortcuts all parse and are unique", Set(Action.allCases.compactMap { KeyCombo.parse($0.defaultShortcut)?.pretty }).count == Action.allCases.count)

    func decode(_ json: String) -> Config? { try? JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
    expect("config: empty object equals defaults", decode("{}") == Config())
    expect("config: crossDisplays defaults to off and can be switched on", decode("{}")?.crossDisplays == false && decode(#"{"crossDisplays": true}"#)?.crossDisplays == true)
    let partial = decode(#"{"gap": 8, "shortcuts": {"maximize": "ctrl+alt+space", "center": ""}, "tile": {"rows": {"5": [2, 3]}}}"#)
    expect("config: partial file keeps other defaults", partial?.gap == 8 && partial?.shortcuts["maximize"] == "ctrl+alt+space"
        && partial?.shortcuts["leftHalf"] == "ctrl+alt+left" && partial?.tile.rows(for: 5) == [2, 3] && partial?.tile.rows(for: 4) == [2, 2])
    expect("config: welcome example parses cleanly", decode(exampleSnippet)?.custom.count == 2 && decode(exampleSnippet)?.warnings().isEmpty == true)
    let bad = decode(#"{"shortcuts": {"nope": "ctrl+a", "center": "what"}, "custom": [{"name": "x", "x": 0.8, "y": 0, "w": 0.5, "h": 1}], "tile": {"rows": {"5": [2, 2]}}}"#)
    expect("config: four problems are reported", bad?.warnings().count == 4, "\(bad?.warnings() ?? [])")
    let dup = decode(#"{"shortcuts": {"maximize": "ctrl+alt+c"}}"#)
    expect("config: two actions on one shortcut are reported", dup?.warnings().contains { $0.contains("center") && $0.contains("maximize") } == true, "\(dup?.warnings() ?? [])")
    expect("config: defaults have no warnings", Config().warnings().isEmpty, "\(Config().warnings())")
    expect("config: broken JSON is an error", decode("{ \"gap\": }") == nil)

    let f = CGRect(x: 0, y: 0, width: 1512, height: 982)
    expect("drag zones: left / right / top", DragSnapper.zone(at: CGPoint(x: 0, y: 500), in: f) == .leftHalf
        && DragSnapper.zone(at: CGPoint(x: 1511, y: 500), in: f) == .rightHalf
        && DragSnapper.zone(at: CGPoint(x: 700, y: 981), in: f) == .maximize)
    expect("drag zones: corners / middle", DragSnapper.zone(at: CGPoint(x: 0, y: 981), in: f) == .topLeft
        && DragSnapper.zone(at: CGPoint(x: 1511, y: 20), in: f) == .bottomRight
        && DragSnapper.zone(at: CGPoint(x: 700, y: 500), in: f) == nil)

    print(fails == 0 ? "all tests passed" : "\(fails) test(s) failed")
    return fails == 0 ? 0 : 1
}

func checkConfig(_ path: String) -> Int32 {
    do {
        let cfg = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let w = cfg.warnings()
        w.forEach { print("warning: \($0)") }
        print(w.isEmpty ? "\(path): OK" : "\(path): \(w.count) problem(s)")
        return w.isEmpty ? 0 : 1
    } catch let e as DecodingError {
        print("\(path): \(ConfigStore.describe(e))"); return 1
    } catch {
        print("\(path): \(error.localizedDescription)"); return 1
    }
}

/// Render each welcome step to a PNG (for the README, and to review UI changes)
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
if args.count > 1, CLI.commands.contains(args[1]) { exit(CLI.run(Array(args.dropFirst()))) }
if args.contains("--selftest") { exit(selfTest()) }
if let i = args.firstIndex(of: "--check"), args.count > i + 1 { exit(checkConfig(args[i + 1])) }
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 { exit(snapshot(to: args[i + 1])) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
