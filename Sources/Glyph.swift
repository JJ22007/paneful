// 布局小图标:一个屏幕轮廓,里面把目标区域涂实。
// 菜单和欢迎界面共用,自定义布局也能自动得到图标。

import AppKit
import SwiftUI

/// 菜单里用的模板图标(自动适配深浅色)
func glyphImage(_ units: [CGRect], size: NSSize = NSSize(width: 18, height: 13)) -> NSImage {
    let img = NSImage(size: size, flipped: true) { rect in
        let frame = rect.insetBy(dx: 0.75, dy: 0.75)
        let outline = NSBezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1.2
        NSColor.black.setStroke()
        outline.stroke()
        let inner = frame.insetBy(dx: 2, dy: 2)
        NSColor.black.setFill()
        for u in units {
            let r = CGRect(x: inner.minX + u.minX * inner.width, y: inner.minY + u.minY * inner.height,
                           width: u.width * inner.width, height: u.height * inner.height)
            NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
        }
        return true
    }
    img.isTemplate = true
    return img
}

/// 欢迎界面里用的大号版本
struct LayoutGlyph: View {
    var units: [CGRect]
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 4
            let w = geo.size.width - pad * 2, h = geo.size.height - pad * 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                ForEach(Array(units.enumerated()), id: \.offset) { _, u in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint)
                        .frame(width: max(u.width * w - 1, 1), height: max(u.height * h - 1, 1))
                        .offset(x: pad + u.minX * w + 0.5, y: pad + u.minY * h + 0.5)
                }
            }
        }
    }
}
