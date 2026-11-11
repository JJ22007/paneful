// 几何计算:全部是纯函数,没有副作用,可以放心改。
// 坐标系:左上角原点、y 向下(和 Accessibility API 一致)。
// "单位矩形"指 0...1 的比例坐标,(0, 0, 0.5, 1) 就是左半屏。

import AppKit

/// 左/右半屏连按时的宽度循环:1/2 → 2/3 → 1/3
let halfCycle: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

/// 内置动作对应的单位矩形。返回 nil 表示这个动作不是"摆到固定位置"(还原、居中、跨屏等)。
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

/// 把单位矩形换算成屏幕上的实际矩形。gap 是窗口之间、窗口与屏幕边缘之间的间距。
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

/// 一键排列的默认规则:n 个窗口每行放几个。
/// 1~3 个排一行;4~6 个排两行;更多排三行。多出来的窗口优先放在上面的行。
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

/// 把窗口按相对比例从一个屏幕搬到另一个屏幕
func remap(_ c: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
    let w = min(c.width / a.width, 1) * b.width, h = min(c.height / a.height, 1) * b.height
    let x = b.minX + (c.minX - a.minX) / a.width * b.width
    let y = b.minY + (c.minY - a.minY) / a.height * b.height
    return CGRect(x: min(max(x, b.minX), b.maxX - w), y: min(max(y, b.minY), b.maxY - h), width: w, height: h).integral
}

func nearlyEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 3) -> Bool {
    abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

/// Cocoa 坐标(左下原点)与 AX 坐标(左上原点)互转。这个变换是自反的。
func flip(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
