// 窗口管理:把"动作"变成"窗口挪到哪"。

import AppKit
import ApplicationServices

final class WindowManager {
    static let shared = WindowManager()

    /// 没有辅助功能权限时被调用(由 App 负责提示用户)
    var onUntrusted: (() -> Void)?

    private var saved: [AXUIElement: CGRect] = [:]    // 分屏前的原始位置,用于"还原"
    private var lastSet: [AXUIElement: CGRect] = [:]  // 我们上次给它设的位置
    private var lastKey: String?
    private var lastWindow: AXUIElement?
    private var cycle = 0

    private var config: Config { ConfigStore.shared.config }
    private var gap: CGFloat { CGFloat(config.gap) }

    /// 与矩形重叠面积最大的屏幕
    func screen(for axFrame: CGRect) -> NSScreen? {
        let cocoa = flip(axFrame)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(cocoa).area < b.frame.intersection(cocoa).area
        } ?? NSScreen.main
    }

    // MARK: 入口

    func perform(_ action: Action, on window: AXUIElement? = nil, screen forced: NSScreen? = nil) {
        guard AX.trusted else { onUntrusted?(); return }
        if action == .tileAll { tileAll(); return }
        guard let w = window ?? AX.focusedWindow(), let cur = AX.frame(of: w) else { NSSound.beep(); return }
        guard let scr = forced ?? screen(for: cur) else { return }
        let visible = flip(scr.visibleFrame)

        switch action {
        case .restore:
            if let r = saved[w] { AX.setFrame(r, of: w); saved[w] = nil; lastSet[w] = nil }
            lastKey = nil
        case .nextDisplay, .prevDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let i = screens.firstIndex(of: scr) else { NSSound.beep(); return }
            let j = (i + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count
            let dest = flip(screens[j].visibleFrame)
            place(w, from: cur, to: remap(cur, from: visible, to: dest), within: dest, key: action.rawValue)
        default:
            // 同一个窗口连按同一个键 → 进入下一档(目前只有左/右半屏有多档)
            let repeated = lastKey == action.rawValue && lastWindow.map { CFEqual($0, w) } == true
                && lastSet[w].map { nearlyEqual($0, cur, tol: 30) } == true
            cycle = repeated ? cycle + 1 : 0
            guard let t = targetRect(action, visible: visible, current: cur, cycle: cycle, gap: gap) else { return }
            place(w, from: cur, to: t, within: visible, key: action.rawValue)
        }
    }

    /// 配置文件里 custom 定义的位置
    func perform(_ layout: CustomLayout) {
        guard AX.trusted else { onUntrusted?(); return }
        guard let w = AX.focusedWindow(), let cur = AX.frame(of: w), let scr = screen(for: cur) else { NSSound.beep(); return }
        let visible = flip(scr.visibleFrame)
        place(w, from: cur, to: screenRect(unit: layout.unit, visible: visible, gap: gap), within: visible, key: "custom:" + layout.name)
    }

    /// 一键排列:每个显示器上各自把可见窗口铺开。超过上限时只排最近用过的那几个,其余不动。
    func tileAll() {
        let all = AX.windowsFrontToBack()
        guard !all.isEmpty else { NSSound.beep(); return }
        var order: [NSScreen] = []
        var byScreen: [NSScreen: [(window: AXUIElement, frame: CGRect)]] = [:]
        for item in all {
            guard let scr = screen(for: item.frame) else { continue }
            if byScreen[scr] == nil { order.append(scr) }
            byScreen[scr, default: []].append(item)
        }
        for scr in order {
            let visible = flip(scr.visibleFrame)
            let chosen = Array(byScreen[scr]!.prefix(max(1, config.tile.max)))
            let rows = config.tile.rows(for: chosen.count)
            // 按窗口现在的位置分配格子(先分行再分列),尽量少挪动
            let byY = chosen.sorted { $0.frame.midY < $1.frame.midY }
            var ordered: [(window: AXUIElement, frame: CGRect)] = []
            var idx = 0
            for cols in rows {
                ordered += byY[idx..<idx + cols].sorted { $0.frame.midX < $1.frame.midX }
                idx += cols
            }
            for (item, target) in zip(ordered, tileLayout(rows: rows, visible: visible, gap: gap)) {
                place(item.window, from: item.frame, to: target, within: nil, key: nil)
            }
        }
        lastKey = nil
    }

    // MARK: 实际挪窗口

    private func place(_ w: AXUIElement, from cur: CGRect, to target: CGRect, within visible: CGRect?, key: String?) {
        // 记住原始位置(只有当它不是我们自己摆的位置时才记)
        if let ls = lastSet[w] { if !nearlyEqual(ls, cur) { saved[w] = cur } } else { saved[w] = cur }

        AX.setFrame(target, of: w)

        // 窗口有最小尺寸时可能超出屏幕,往回推一下
        if let v = visible, let actual = AX.frame(of: w) {
            var o = actual.origin
            if actual.maxX > v.maxX { o.x = max(v.minX, v.maxX - actual.width) }
            if actual.maxY > v.maxY { o.y = max(v.minY, v.maxY - actual.height) }
            if o != actual.origin { AX.setOrigin(o, of: w) }
        }

        lastSet[w] = AX.frame(of: w) ?? target
        lastKey = key
        lastWindow = w
    }
}
