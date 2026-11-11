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
    case .center, .restore, .nextDisplay, .prevDisplay, .tileAll: return nil
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

/// The display one step to the left or right of frames[i], or nil with a single display.
/// Displays are ordered left to right (top to bottom when stacked) and the order wraps around,
/// so the key keeps working however the displays are arranged.
func neighborDisplay(of i: Int, in frames: [CGRect], left: Bool) -> Int? {
    guard frames.count > 1 else { return nil }
    let order = frames.indices.sorted { (frames[$0].minX, frames[$0].minY) < (frames[$1].minX, frames[$1].minY) }
    guard let at = order.firstIndex(of: i) else { return nil }
    return order[(at + (left ? order.count - 1 : 1)) % order.count]
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
