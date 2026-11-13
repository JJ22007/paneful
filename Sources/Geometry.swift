// Geometry: pure functions with no side effects, safe to change.
// Coordinates: top-left origin, y pointing down (same as the Accessibility API).
// A "unit rect" is in 0...1 fractions of the screen: (0, 0, 0.5, 1) is the left half.

import AppKit

/// Widths cycled through when left/right half is pressed repeatedly: 1/2 → 2/3 → 1/3
let halfCycle: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

/// The unit rect of a built-in action. nil means the action is not a fixed position (restore, center, displays…).
func unitRect(for a: Action, cycle: Int = 0) -> CGRect? {
    switch a {
    case .leftHalf: return CGRect(x: 0, y: 0, width: halfCycle[cycle % 3], height: 1)
    case .rightHalf:
        let w = halfCycle[cycle % 3]
        return CGRect(x: 1 - w, y: 0, width: w, height: 1)
    case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
    case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
    case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
    case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
    case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    case .firstThird: return CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
    case .centerThird: return CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
    case .lastThird: return CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
    case .firstTwoThirds: return CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
    case .lastTwoThirds: return CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
    case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
    case .almostMaximize: return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    case .center, .restore, .nextDisplay, .prevDisplay, .focusNextDisplay, .tileAll: return nil
    }
}

/// Turn a unit rect into a real rect on screen. gap is the space between windows and around the screen edge.
func screenRect(unit u: CGRect, visible v: CGRect, gap: CGFloat = 0) -> CGRect {
    let area = v.insetBy(dx: gap / 2, dy: gap / 2)
    return CGRect(x: area.minX + u.minX * area.width, y: area.minY + u.minY * area.height,
                  width: u.width * area.width, height: u.height * area.height)
        .insetBy(dx: gap / 2, dy: gap / 2).integral
}

func targetRect(_ a: Action, visible v: CGRect, current c: CGRect, cycle: Int = 0, gap: CGFloat = 0) -> CGRect? {
    if a == .center {
        let w = min(c.width, v.width), h = min(c.height, v.height)
        return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
    }
    return unitRect(for: a, cycle: cycle).map { screenRect(unit: $0, visible: v, gap: gap) }
}

/// Default rule for "tile all": how many of n windows go in each row.
/// 1–3 windows share one row, 4–6 use two rows, more use three. Extra windows go to the upper rows first.
func defaultTileRows(_ n: Int) -> [Int] {
    guard n > 0 else { return [] }
    if n <= 3 { return [n] }
    let r = n <= 6 ? 2 : 3
    return (0..<r).map { n / r + ($0 < n % r ? 1 : 0) }
}

func tileLayout(rows: [Int], visible v: CGRect, gap: CGFloat = 0) -> [CGRect] {
    var out: [CGRect] = []
    for (ri, cols) in rows.enumerated() where cols > 0 {
        let h = 1.0 / CGFloat(rows.count), w = 1.0 / CGFloat(cols)
        for ci in 0..<cols {
            out.append(screenRect(unit: CGRect(x: CGFloat(ci) * w, y: CGFloat(ri) * h, width: w, height: h), visible: v, gap: gap))
        }
    }
    return out
}

/// Move a window to another screen, keeping its relative position and size
func remap(_ c: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
    let w = min(c.width / a.width, 1) * b.width, h = min(c.height / a.height, 1) * b.height
    let x = b.minX + (c.minX - a.minX) / a.width * b.width
    let y = b.minY + (c.minY - a.minY) / a.height * b.height
    return CGRect(x: min(max(x, b.minX), b.maxX - w), y: min(max(y, b.minY), b.maxY - h), width: w, height: h).integral
}

/// True when the window already hugs the edge it is walking toward (and only that edge),
/// which means the next step of a walk leaves this display.
func onOuterHalf(_ c: CGRect, visible v: CGRect, right: Bool, tol: CGFloat = 30) -> Bool {
    let atLeft = abs(c.minX - v.minX) <= tol, atRight = abs(c.maxX - v.maxX) <= tol
    return right ? (atRight && !atLeft) : (atLeft && !atRight)
}

/// Display indices sorted left to right, then top to bottom. `paneful --display N` counts in this order.
func displayOrder(_ frames: [CGRect]) -> [Int] {
    frames.indices.sorted { (frames[$0].minX, frames[$0].minY) < (frames[$1].minX, frames[$1].minY) }
}

/// The display one step to the left or right of frames[i], or nil with a single display.
/// Displays are ordered left to right (top to bottom when stacked) and the order wraps around,
/// so the key keeps working however the displays are arranged.
func neighborDisplay(of i: Int, in frames: [CGRect], left: Bool) -> Int? {
    guard frames.count > 1 else { return nil }
    let order = displayOrder(frames)
    guard let at = order.firstIndex(of: i) else { return nil }
    return order[(at + (left ? order.count - 1 : 1)) % order.count]
}

/// Which windows Restore puts back after tile all. `placed` is where tile all left each window,
/// `now` where each one is (nil if it is gone). If the focused window still sits where tile all
/// put it, every window that also still does goes back together; otherwise only the focused one.
func tileUndoGroup(focused: Int, placed: [CGRect], now: [CGRect?], tol: CGFloat = 30) -> [Int] {
    func still(_ i: Int) -> Bool { now[i].map { nearlyEqual($0, placed[i], tol: tol) } == true }
    guard placed.indices.contains(focused), still(focused) else { return [focused] }
    return placed.indices.filter(still)
}

func nearlyEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 3) -> Bool {
    abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

/// Convert between Cocoa (bottom-left origin) and AX (top-left origin) coordinates. The transform is its own inverse.
func flip(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

// MARK: Tile all, with room for windows that refuse to shrink

/// A tile-all layout: slots side by side (`across`) or stacked (`down`), nested.
/// `across` takes relative widths; a slot that is `empty` is left free on purpose.
indirect enum Tile: Equatable {
    case window
    case empty
    case across([Tile], weights: [CGFloat])
    case down([Tile])

    static func across(_ ts: [Tile]) -> Tile { .across(ts, weights: ts.map { _ in 1 }) }

    var windowCount: Int {
        switch self {
        case .window: return 1
        case .empty: return 0
        case .across(let ts, _): return ts.reduce(0) { $0 + $1.windowCount }
        case .down(let ts): return ts.reduce(0) { $0 + $1.windowCount }
        }
    }
}

/// Named layouts for tile all, chosen per window count with `tile.shapes` in the config
enum TileShapeName: String, CaseIterable {
    case columns        // everything side by side
    case grid           // columns of two; with an odd count one corner stays free
    case gridSidebar    // a grid of the rest, plus a full-height sidebar on the right
}

/// The layout for n windows. `rows` (from the config) wins, then `shape`, then the default:
/// 2–3 side by side, 4 and 6 as a grid, 5 as a 2×2 grid with a sidebar, more in rows.
/// Grids are built from whole columns, so a window that needs more width widens its column, not just its cell.
func tileShape(_ n: Int, rows custom: [Int]? = nil, shape: TileShapeName? = nil) -> Tile {
    if let r = custom { return .down(r.map { .across(Array(repeating: Tile.window, count: $0)) }) }
    if n <= 1 { return .window }
    func grid(_ k: Int) -> [Tile] {
        stride(from: 0, to: k, by: 2).map { i in .down([.window, i + 1 < k ? .window : .empty]) }
    }
    let pick = shape ?? (n <= 3 ? .columns : n == 5 ? .gridSidebar : n <= 6 ? .grid : nil)
    switch pick {
    case .columns: return .across(Array(repeating: Tile.window, count: n))
    case .grid: return .across(grid(n))
    case .gridSidebar:
        let g = grid(n - 1)
        return .across(g + [.window], weights: g.map { _ in 3 } + [2])
    case nil: return .down(defaultTileRows(n).map { .across(Array(repeating: Tile.window, count: $0)) })
    }
}

/// Split `total` by weight, but keep each part within its smallest and largest size: parts that need
/// more get it, parts that can't grow get no more than they take, and the rest share what is left.
/// If even the minimums don't fit, each part gets its minimum.
func shareOut(_ total: CGFloat, weights: [CGFloat], mins: [CGFloat], maxs: [CGFloat]? = nil) -> [CGFloat] {
    let maxs = maxs ?? mins.map { _ in .infinity }
    var out = mins.map { _ in CGFloat(0) }, fixed = mins.map { _ in false }
    while true {
        let flex = out.indices.filter { !fixed[$0] }
        if flex.isEmpty { return out }
        let rest = total - out.indices.filter { fixed[$0] }.reduce(0) { $0 + out[$1] }
        let wsum = flex.reduce(0) { $0 + weights[$1] }
        let share = { (i: Int) in rest * weights[i] / wsum }
        let low = flex.filter { mins[$0] > share($0) + 0.5 }
        let high = flex.filter { maxs[$0] < share($0) - 0.5 }
        // Settle the needier side first: a part that needs more shrinks everyone else's share
        if !low.isEmpty { for i in low { fixed[i] = true; out[i] = mins[i] }; continue }
        if !high.isEmpty { for i in high { fixed[i] = true; out[i] = max(mins[i], maxs[i]) }; continue }
        for i in flex { out[i] = max(0, share(i)) }
        return out
    }
}

/// Frames for the window slots of `t`, in depth-first order. `mins` and `maxs` are the smallest and largest
/// sizes the windows take (zero and infinity when unknown), in the same order. Frames stay on screen even
/// when the minimums don't fit.
func tileFrames(_ t: Tile, visible v: CGRect, gap: CGFloat = 0, mins: [CGSize] = [], maxs: [CGSize] = []) -> [CGRect] {
    let area = v.insetBy(dx: gap, dy: gap)
    let inf = CGFloat.infinity
    var next = 0
    // (min, max) of a subtree, along the width or the height
    func limits(_ t: Tile, _ wide: Bool, from k: inout Int) -> (CGFloat, CGFloat) {
        switch t {
        case .window:
            defer { k += 1 }
            let lo = k < mins.count ? (wide ? mins[k].width : mins[k].height) : 0
            let hi = k < maxs.count ? (wide ? maxs[k].width : maxs[k].height) : inf
            return (lo, hi)
        case .empty: return (0, inf)
        case .across(let ts, _), .down(let ts):
            let along: Bool = { if case .across = t { return wide } else { return !wide } }()
            let ls = ts.map { limits($0, wide, from: &k) }
            if along { return (ls.reduce(0) { $0 + $1.0 } + gap * CGFloat(ts.count - 1), ls.reduce(0) { $0 + $1.1 } + gap * CGFloat(ts.count - 1)) }
            // Side by side the other way: the largest minimum, and room for the most flexible
            return (ls.map(\.0).max() ?? 0, ls.map(\.1).max() ?? inf)
        }
    }
    var out: [CGRect] = []
    func lay(_ t: Tile, in r: CGRect) {
        switch t {
        case .window:
            let lo = next < mins.count ? mins[next] : .zero
            let hi = next < maxs.count ? maxs[next] : CGSize(width: inf, height: inf)
            next += 1
            let w = min(r.width, hi.width), h = min(r.height, hi.height)
            // Keep a window that will be wider or taller than its slot from running off the screen
            let x = min(r.minX, area.maxX - max(w, lo.width)), y = min(r.minY, area.maxY - max(h, lo.height))
            out.append(CGRect(x: max(area.minX, x), y: max(area.minY, y), width: w, height: h).integral)
        case .empty: break
        case .across(let ts, let weights):
            var k = next
            let ls = ts.map { limits($0, true, from: &k) }
            let ws = shareOut(r.width - gap * CGFloat(ts.count - 1), weights: weights, mins: ls.map(\.0), maxs: ls.map(\.1))
            var x = r.minX
            for (t, w) in zip(ts, ws) { lay(t, in: CGRect(x: x, y: r.minY, width: w, height: r.height)); x += w + gap }
        case .down(let ts):
            var k = next
            let ls = ts.map { limits($0, false, from: &k) }
            let hs = shareOut(r.height - gap * CGFloat(ts.count - 1), weights: ts.map { _ in 1 }, mins: ls.map(\.0), maxs: ls.map(\.1))
            var y = r.minY
            for (t, h) in zip(ts, hs) { lay(t, in: CGRect(x: r.minX, y: y, width: r.width, height: h)); y += h + gap }
        }
    }
    lay(t, in: area)
    return out
}

/// Which window goes in which slot: front windows choose first, each taking the free slot nearest to where it is,
/// so windows move as little as possible. Returns, for each window, the index of its slot.
func assignSlots(windows: [CGRect], slots: [CGRect]) -> [Int] {
    var free = Set(slots.indices)
    return windows.map { w in
        let s = free.min { a, b in
            hypot(slots[a].midX - w.midX, slots[a].midY - w.midY) < hypot(slots[b].midX - w.midX, slots[b].midY - w.midY)
        }!
        free.remove(s)
        return s
    }
}
