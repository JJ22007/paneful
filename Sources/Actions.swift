// 内置动作。想加一个新动作:在这里加一个 case,填上标题和默认快捷键,
// 然后在 Geometry.swift 的 unitRect(for:) 里给它一个位置。

import AppKit

enum Action: String, CaseIterable {
    case tileAll
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, center, restore
    case nextDisplay, prevDisplay

    var title: String {
        switch self {
        case .tileAll: return "一键排列所有窗口"
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .topLeft: return "左上 1/4"
        case .topRight: return "右上 1/4"
        case .bottomLeft: return "左下 1/4"
        case .bottomRight: return "右下 1/4"
        case .firstThird: return "左 1/3"
        case .centerThird: return "中 1/3"
        case .lastThird: return "右 1/3"
        case .firstTwoThirds: return "左 2/3"
        case .lastTwoThirds: return "右 2/3"
        case .maximize: return "最大化"
        case .almostMaximize: return "接近最大化"
        case .center: return "居中"
        case .restore: return "还原"
        case .nextDisplay: return "移到下一个显示器"
        case .prevDisplay: return "移到上一个显示器"
        }
    }

    /// 默认快捷键,和 Rectangle 的默认值一致。用户可以在配置文件的 shortcuts 里覆盖。
    var defaultShortcut: String {
        switch self {
        case .tileAll: return "ctrl+alt+a"
        case .leftHalf: return "ctrl+alt+left"
        case .rightHalf: return "ctrl+alt+right"
        case .topHalf: return "ctrl+alt+up"
        case .bottomHalf: return "ctrl+alt+down"
        case .topLeft: return "ctrl+alt+u"
        case .topRight: return "ctrl+alt+i"
        case .bottomLeft: return "ctrl+alt+j"
        case .bottomRight: return "ctrl+alt+k"
        case .firstThird: return "ctrl+alt+d"
        case .centerThird: return "ctrl+alt+f"
        case .lastThird: return "ctrl+alt+g"
        case .firstTwoThirds: return "ctrl+alt+e"
        case .lastTwoThirds: return "ctrl+alt+t"
        case .maximize: return "ctrl+alt+return"
        case .almostMaximize: return "ctrl+alt+m"
        case .center: return "ctrl+alt+c"
        case .restore: return "ctrl+alt+delete"
        case .nextDisplay: return "ctrl+alt+cmd+right"
        case .prevDisplay: return "ctrl+alt+cmd+left"
        }
    }

    /// 菜单里的分组
    static let groups: [[Action]] = [
        [.tileAll],
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
        [.maximize, .almostMaximize, .center, .restore],
        [.nextDisplay, .prevDisplay],
    ]

    /// 小图标里要涂实的区域(单位矩形)
    var glyphUnits: [CGRect] {
        switch self {
        case .tileAll:
            return [CGRect(x: 0, y: 0, width: 0.46, height: 0.44), CGRect(x: 0.54, y: 0, width: 0.46, height: 0.44),
                    CGRect(x: 0, y: 0.56, width: 0.46, height: 0.44), CGRect(x: 0.54, y: 0.56, width: 0.46, height: 0.44)]
        case .center: return [CGRect(x: 0.25, y: 0.22, width: 0.5, height: 0.56)]
        case .restore: return [CGRect(x: 0.15, y: 0.2, width: 0.45, height: 0.5)]
        case .nextDisplay: return [CGRect(x: 0.6, y: 0, width: 0.4, height: 1)]
        case .prevDisplay: return [CGRect(x: 0, y: 0, width: 0.4, height: 1)]
        default: return unitRect(for: self).map { [$0] } ?? []
        }
    }
}
