// 拖到屏幕边缘吸附:拖着窗口碰到屏幕边缘时显示预览框,松手后摆到对应位置。
// 默认关闭,因为 macOS 自带的拖边平铺会和它同时出现。

import AppKit
import ApplicationServices

final class OverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .floating
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 12
        contentView = v
    }
}

final class DragSnapper {
    private var monitor: Any?
    private var window: AXUIElement?
    private var initial: CGRect?
    private var moving = false
    private var target: (action: Action, screen: NSScreen)?
    private lazy var overlay = OverlayWindow()

    var enabled: Bool { monitor != nil }

    func setEnabled(_ on: Bool) {
        if on, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
                self?.handle(e)
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            reset()
        }
    }

    private func reset() {
        window = nil; initial = nil; moving = false
        if target != nil { overlay.orderOut(nil) }
        target = nil
    }

    /// 鼠标贴到哪条边 → 对应哪个动作。想改吸附规则就改这里。(Cocoa 坐标,y 向上)
    static func zone(at p: CGPoint, in f: CGRect) -> Action? {
        let edge: CGFloat = 4, corner: CGFloat = 120
        let l = p.x <= f.minX + edge, r = p.x >= f.maxX - edge - 1
        let t = p.y >= f.maxY - edge - 1, b = p.y <= f.minY + edge
        let nearTop = p.y >= f.maxY - corner, nearBottom = p.y <= f.minY + corner
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner
        if (l && nearTop) || (t && nearLeft) { return .topLeft }
        if (r && nearTop) || (t && nearRight) { return .topRight }
        if (l && nearBottom) || (b && nearLeft) { return .bottomLeft }
        if (r && nearBottom) || (b && nearRight) { return .bottomRight }
        if l { return .leftHalf }
        if r { return .rightHalf }
        if t { return .maximize }
        return nil
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged:
            guard AX.trusted else { return }
            if window == nil {
                guard let w = AX.focusedWindow(), let f = AX.frame(of: w) else { return }
                window = w; initial = f
                return
            }
            let p = NSEvent.mouseLocation
            guard let scr = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame.insetBy(dx: -1, dy: -1), false) }),
                  let action = DragSnapper.zone(at: p, in: scr.frame) else {
                if target != nil { target = nil; overlay.orderOut(nil) }
                return
            }
            if !moving {
                // 只有窗口真的在被拖动(位置变了、大小没变)才算
                guard let w = window, let ini = initial, let cur = AX.frame(of: w) else { return }
                moving = cur.origin != ini.origin && abs(cur.width - ini.width) < 2 && abs(cur.height - ini.height) < 2
                if !moving { return }
            }
            if target?.action != action || target?.screen != scr {
                target = (action, scr)
                let gap = CGFloat(ConfigStore.shared.config.gap)
                if let r = targetRect(action, visible: flip(scr.visibleFrame), current: initial ?? .zero, gap: gap) {
                    overlay.setFrame(flip(r), display: true)
                    overlay.orderFrontRegardless()
                }
            }
        case .leftMouseUp:
            if moving, let t = target, let w = window {
                WindowManager.shared.perform(t.action, on: w, screen: t.screen)
            }
            reset()
        default: break
        }
    }
}
