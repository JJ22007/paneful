// Window management: turn an action into "this window goes there".

import AppKit
import ApplicationServices

final class WindowManager {
    static let shared = WindowManager()

    /// Called when the Accessibility permission is missing (the app tells the user)
    var onUntrusted: (() -> Void)?

    private var saved: [AXUIElement: CGRect] = [:]    // frame before we touched the window, for Restore
    private var lastSet: [AXUIElement: CGRect] = [:]  // the frame we last set
    private var lastKey: String?
    private var lastWindow: AXUIElement?
    private var cycle = 0
    /// Where the last move asked a window to go, so the CLI can compare it with where the window ended up
    var lastTarget: CGRect?

    private var config: Config { ConfigStore.shared.config }
    private var gap: CGFloat { CGFloat(config.gap) }

    /// The screen that overlaps the rect the most
    func screen(for axFrame: CGRect) -> NSScreen? {
        let cocoa = flip(axFrame)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(cocoa).area < b.frame.intersection(cocoa).area
        } ?? NSScreen.main
    }

    // MARK: Entry points

    func perform(_ action: Action, on window: AXUIElement? = nil, screen forced: NSScreen? = nil) {
        guard AX.trusted else { onUntrusted?(); return }
        if action == .tileAll { tileAll(); return }
        guard let w = window ?? AX.focusedWindow(), let cur = AX.frame(of: w) else { NSSound.beep(); return }
        guard let scr = forced ?? screen(for: cur) else { return }
        let visible = flip(scr.visibleFrame)

        switch action {
        case .restore:
            if let r = saved[w] { AX.setFrame(r, of: w); saved[w] = nil; lastSet[w] = nil; lastTarget = r }
            lastKey = nil
        case .nextDisplay, .prevDisplay:
            // Walk the window one half at a time across every display:
            // left half → right half → next display's left half → its right half → …
            let right = action == .nextDisplay
            var dest = visible
            var half: Action = right ? .rightHalf : .leftHalf
            if onOuterHalf(cur, visible: visible, right: right, tol: 30 + gap) {
                guard let i = NSScreen.screens.firstIndex(of: scr),
                      let j = neighborDisplay(of: i, in: NSScreen.screens.map { flip($0.frame) }, left: !right) else { NSSound.beep(); return }
                dest = flip(NSScreen.screens[j].visibleFrame)
                half = right ? .leftHalf : .rightHalf
            }
            guard let t = targetRect(half, visible: dest, current: cur, gap: gap) else { return }
            place(w, from: cur, to: t, within: dest, key: action.rawValue)
        default:
            // Same key again on the same window → next step in the cycle (only the halves have steps today)
            var repeated = lastKey == action.rawValue && lastWindow.map { CFEqual($0, w) } == true
                && lastSet[w].map { nearlyEqual($0, cur, tol: 30) } == true
            // The window may already sit on one of this action's steps without this key having put it
            // there (another key, the mouse, tile all). Continue from that step so no press is wasted.
            if !repeated, let k = (0..<halfCycle.count).first(where: { i in
                targetRect(action, visible: visible, current: cur, cycle: i, gap: gap).map { nearlyEqual($0, cur, tol: 30) } == true
            }) {
                repeated = true
                cycle = k
            }
            // With a display on that side, the second press of left/right half carries the window
            // over to it: left half → right half of the display on the left, and the other way round.
            if repeated, config.crossDisplays, action == .leftHalf || action == .rightHalf,
               let i = NSScreen.screens.firstIndex(of: scr),
               let j = neighborDisplay(of: i, in: NSScreen.screens.map { flip($0.frame) }, left: action == .leftHalf) {
                let dest = flip(NSScreen.screens[j].visibleFrame)
                let far: Action = action == .leftHalf ? .rightHalf : .leftHalf
                guard let t = targetRect(far, visible: dest, current: cur, gap: gap) else { return }
                // A different key, so the next press lands on this display's own half instead of crossing again
                place(w, from: cur, to: t, within: dest, key: action.rawValue + ":crossed")
                cycle = 0
                return
            }
            cycle = repeated ? cycle + 1 : 0
            guard let t = targetRect(action, visible: visible, current: cur, cycle: cycle, gap: gap) else { return }
            place(w, from: cur, to: t, within: visible, key: action.rawValue)
        }
    }

    /// A position defined under `custom` in the config
    func perform(_ layout: CustomLayout, on window: AXUIElement? = nil, screen forced: NSScreen? = nil) {
        guard AX.trusted else { onUntrusted?(); return }
        guard let w = window ?? AX.focusedWindow(), let cur = AX.frame(of: w), let scr = forced ?? screen(for: cur) else { NSSound.beep(); return }
        let visible = flip(scr.visibleFrame)
        place(w, from: cur, to: screenRect(unit: layout.unit, visible: visible, gap: gap), within: visible, key: "custom:" + layout.name)
    }

    /// Tile all: spread the visible windows on each display. Above the limit, only the most recent ones are tiled.
    /// Returns each window that was moved and the frame it was asked to take.
    @discardableResult
    func tileAll() -> [(window: AXUIElement, target: CGRect)] {
        let all = AX.windowsFrontToBack()
        guard !all.isEmpty else { NSSound.beep(); return [] }
        var placed: [(window: AXUIElement, target: CGRect)] = []
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
            // Assign cells by where windows already are (rows first, then columns) so they move as little as possible
            let byY = chosen.sorted { $0.frame.midY < $1.frame.midY }
            var ordered: [(window: AXUIElement, frame: CGRect)] = []
            var idx = 0
            for cols in rows {
                ordered += byY[idx..<idx + cols].sorted { $0.frame.midX < $1.frame.midX }
                idx += cols
            }
            for (item, target) in zip(ordered, tileLayout(rows: rows, visible: visible, gap: gap)) {
                place(item.window, from: item.frame, to: target, within: nil, key: nil)
                placed.append((item.window, target))
            }
        }
        lastKey = nil
        return placed
    }

    /// Put a window back at an exact frame (used by `paneful restore`). Restore can undo it like any other move.
    func move(_ w: AXUIElement, to frame: CGRect) {
        guard let cur = AX.frame(of: w) else { return }
        place(w, from: cur, to: frame, within: nil, key: nil)
        lastKey = nil
    }

    // MARK: Moving windows

    private func place(_ w: AXUIElement, from cur: CGRect, to target: CGRect, within visible: CGRect?, key: String?) {
        // Remember the original frame (only if the current one is not a frame we set)
        if let ls = lastSet[w] { if !nearlyEqual(ls, cur) { saved[w] = cur } } else { saved[w] = cur }
        lastTarget = target

        AX.setFrame(target, of: w)

        // A window with a minimum size can overflow the screen; nudge it back
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
