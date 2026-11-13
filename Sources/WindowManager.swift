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
        if action == .focusNextDisplay { focusNextDisplay(); return }
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

    /// Move the focus, not a window, to the next display: activate the frontmost window there and
    /// put the pointer on it, so the next shortcut (and macOS's own ⌃←/→ for Spaces) acts on that display.
    /// Returns the display it went to, numbered like `paneful displays`.
    @discardableResult
    func focusNextDisplay() -> Int? {
        let screens = NSScreen.screens
        let frames = screens.map { flip($0.frame) }
        let mouse = flip(CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1))).origin
        // Start from the display with the focused window, or the one under the pointer
        let here = AX.focusedWindow().flatMap { AX.frame(of: $0) }.flatMap { screen(for: $0) }.flatMap { screens.firstIndex(of: $0) }
            ?? frames.firstIndex { $0.contains(mouse) } ?? 0
        guard let j = neighborDisplay(of: here, in: frames, left: false) else { NSSound.beep(); return nil }
        let dest = screens[j]
        var point = CGPoint(x: frames[j].midX, y: frames[j].midY)
        if let top = AX.windowsFrontToBack().first(where: { screen(for: $0.frame) == dest }) {
            var pid: pid_t = 0
            AXUIElementGetPid(top.window, &pid)
            AXUIElementPerformAction(top.window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(top.window, kAXMainAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
            point = CGPoint(x: top.frame.midX, y: top.frame.midY)
        }
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        return displayOrder(frames).firstIndex(of: j).map { $0 + 1 }
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
            let shape = tileShape(chosen.count, rows: config.tile.customRows(for: chosen.count))
            var mins = [CGSize](repeating: .zero, count: chosen.count)
            var slots = tileFrames(shape, visible: visible, gap: gap)
            let slotOf = assignSlots(windows: chosen.map(\.frame), slots: slots)
            for (item, k) in zip(chosen, slotOf) { place(item.window, from: item.frame, to: slots[k], within: nil, key: nil) }
            // Many apps won't go below a minimum size. Read the windows back; where one came out bigger
            // than its slot, give it that much room and let the others share the rest. Repeat while that
            // squeezes another window below its own minimum.
            for _ in 0..<3 {
                let got = settle(chosen.indices.map { (chosen[$0].window, slots[slotOf[$0]]) })
                var grew = false
                for (i, k) in slotOf.enumerated() {
                    let want = slots[k], have = got[i]
                    if have.width > want.width + 2, have.width > mins[k].width { mins[k].width = have.width; grew = true }
                    if have.height > want.height + 2, have.height > mins[k].height { mins[k].height = have.height; grew = true }
                }
                guard grew else { break }
                slots = tileFrames(shape, visible: visible, gap: gap, mins: mins)
                for (item, k) in zip(chosen, slotOf) {
                    AX.setFrame(slots[k], of: item.window)
                    lastSet[item.window] = slots[k]
                }
            }
            for (item, k) in zip(chosen, slotOf) { placed.append((item.window, slots[k])) }
        }
        lastKey = nil
        return placed
    }

    /// Wait until the windows reach their targets (or stop moving), and return where they are
    private func settle(_ moves: [(window: AXUIElement, target: CGRect)]) -> [CGRect] {
        var frames: [CGRect] = []
        for _ in 0..<12 {
            let now = moves.map { AX.frame(of: $0.window) ?? $0.target }
            if zip(now, moves).allSatisfy({ nearlyEqual($0, $1.target, tol: 3) }) || now == frames { return now }
            frames = now
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return frames
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
